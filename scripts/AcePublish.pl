#!/usr/local/bin/perl5.6.1 -w
#
# AcePublish.pl
#
# by Alessandro Guffanti
#
# Last updated on: $Date: 2002-12-09 12:08:48 $
# Last updated by: $Author: krb $
#
# AcePublish.pl will produce a new cgcace version from autoace or will produce diff files 
# between two different versions of the database

use lib "/wormsrv2/scripts/";
use Wormbase;

use Cwd;
use IPC::Open2;
use POSIX qw(:signal_h :errno_h :sys_wait_h);
use IO::Handle;
use File::Basename;
use File::Find;
use Getopt::Std;

getopts ('nuv:');


# Create touch file to record script activity
$0 =~ m/\/([^\/]+)$/;
system ("touch /wormsrv2/logs/history/$1.'date +%y%m%d'");



$|=1;



# Avoid filling process table with zombies
$SIG{CHLD} = \&REAPER;
sub REAPER {
  my $pid;
  $pid=waitpid(-1,&WNOHANG);
  $SIG{CHLD}=\&REAPER;
}

my $CWD = cwd;
$ENV{PATH}="/nfs/disk100/acedb/RELEASE.SUPPORTED/bin.ALPHA_4:$ENV{PATH}";
my $LOG="AcePublish.log.$$";
my $PRESENT_DIR = cwd;
$PRESENT_DIR =~ s/\/tmp_mnt//;
my $LOGFILE = "$PRESENT_DIR"."/"."$LOG";

$tace = &tace; 
#"/nfs/disk100/acedb/RELEASE.SUPPORTED/bin.ALPHA_4/tace";
$autoace = "$tace /nfs/disk100/wormpub/autoace";
$cgcace = "$tace /nfs/disk100/wormpub/acedb/ace4/cgc";

#$aceclient = "/nfs/disk100/acedb/RELEASE.SUPPORTED/bin.ALPHA_4/aceclient";
#$autoace = "$aceclient wormsrv1 -port 210202";
#$cgcace = "$aceclient wormsrv1 -port 210201";

#---------------------------------------
# Update:  dumps ace files for all
# the relevant classes and acediff
#
if (($opt_u)&&(!$opt_n)) {
  my $acediff = "/nfs/disk100/acedb/RELEASE.SUPPORTED/bin.ALPHA_4/acediff";
  my $updatedir = "/nfs/disk100/wormpub2/ag3/DIFF";
  my $oldupdatedir = "/nfs/disk100/wormpub2/ag3/DIFF/old";
  my $newupdatedir = "/nfs/disk100/wormpub2/ag3/DIFF/new";
  my $diffdir = "/nfs/disk100/wormpub2/ag3/DIFF/diff";

#  my $updatedir = "/nfs/disk100/wormpub/ACEDIFF";
#  my $oldupdatedir = "/nfs/disk100/wormpub/ACEDIFF/old";
#  my $newupdatedir = "/nfs/disk100/wormpub/ACEDIFF/new";
#  my $diffdir = "/nfs/disk100/wormpub/ACEDIFF/diff";

  print "Update procedure STARTED - Log can be retrieved in $LOGFILE\n";
  open (LOGFILE,">$LOGFILE");
  LOGFILE->autoflush();
# The complete set of classes to dump is between the DATA and END tokens
READARRAY: while (<DATA>) {
    chomp $_;
    last READARRAY if $_ =~ /END/;
    push (@TotalClasses,$_);
  }

# If DEBUG uncomment this - it will substitute the @TotalClasses array

#  @TotalClasses = ();
#  @TotalClasses = qw(Method Paper Locus Allele Author);

# Start
  my $TODAY=&GetTime;
  print LOGFILE "AcePublish Update run $$ started $TODAY\n";

# Dump Autoace classes
  print LOGFILE "\n *1) Dumping AUTO_ classes for $autoace ..\n\n";
  &DumpAce("AUTO_",$autoace,$updatedir);
# Dump CGCace classes
  print LOGFILE "\n *2) Dumping CGC_ classes for $cgcace ..\n\n";
  &DumpAce("CGC_",$cgcace,$updatedir);
# Update the archive of ace dumps
  print LOGFILE "\n *3) Updating ace dump archives ..\n\n";
  &MoveAce($oldupdatedir,$newupdatedir,$updatedir);
# Compare ace files and produce diff files
  print LOGFILE "\n *4) Acediffing ..\n\n";
  &DiffAce($newupdatedir,$diffdir,$acediff);    
# Produce the tarred update file 
  print LOGFILE "\n *5) Producing the update raw data file ..\n\n";
  &RawData($diffdir);
# The end
  $TODAY=&GetTime;
  print LOGFILE "\nAcePublish Finished OK $TODAY\n";
  close LOGFILE;
  exit 0;
  
#---------------------------------------
# New_version: transfers the new autoace
# in cgcace and also updates ftp site
#
} elsif (($opt_n)&&($opt_v)&&(!$opt_u)) {
  chomp $opt_v;
  my $version = "WS"."$opt_v";
  my $TransferDB="/nfs/disk100/wormpub/analysis/scripts/TransferDB";
  my $autodir1="/nfs/wormdata1/wormdb2";
  my $autodir2="/nfs/disk100/wormpub/acedb/ace4/autoace";
  my $srcdir="$autodir2/release";
  my $s_chrdir="/nfs/disk100/wormpub/autoace/CHROMOSOMES";
#  my $cgcdir="/nfs/disk100/wormpub2/ag3/FAKE_CGC";
#  my $ftpdir="/nfs/disk100/wormpub2/ag3/FAKE_FTP";
#  my $e_chrdir="/nfs/disk100/wormpub2/ag3/FAKE_CHROMOSOMES."."$version";
   my $cgcdir = "/nfs/wormdata1/wormdb";
   my $ftpdir="/nfs/disk69/ftp/pub2/acedb/celegans/new_release";
   my $e_chrdir="/nfs/disk69/ftp/pub2/acedb/celegans/new_release/CHROMOSOMES."."$version";
  open (LOGFILE,">$LOGFILE");
  LOGFILE->autoflush();
  $TODAY=&GetTime;
  print LOGFILE "AcePublish new version procedure STARTED at $TODAY\n";  

# Transfer AUTOACE distribution compressed files to ftp directory 
  print LOGFILE "\n* 1) Transferring AUTOACE distribution compressed files to ftp directory ..\n\n";
  system "/bin/rm -r $ftpdir/database.*";
  &TransferToFTP($srcdir,$ftpdir);
# Transfer AUTOACE CHROMOSOMES compressed files to ftp directory
  print LOGFILE "\n* 2) Transferring CHROMOSOMES compressed files to ftp directory ..\n\n";
  system "/bin/rm -rf $e_chrdir/*";
  &TransferToFTP($s_chrdir,$e_chrdir);
# Shut down wormace server
  print LOGFILE "\n* 3) Shutting down wormace before database transfer .. \n\n";
  &ShutDownCGC($cgcace);
# Transfer autoace /database to cgcace
  print LOGFILE "\n* 4) Transferring autoace /database to cgcace .. \n\n";
  `$TransferDB \-start\=$autodir1 \-end\=$cgcdir \-database \-printlog 1>>$LOGFILE`;
# Transfer autoace /wspec to cgcace
  print LOGFILE "\n* 5) Transferring autoace /wspec to cgcace .. \n\n";
  `$TransferDB \-start\=$autodir2 \-end\=$cgcdir \-name\=cgcace \-wspec \-printlog 1>>$LOGFILE`;
  my $TODAY=&GetTime;
  print LOGFILE "\nAcePublish new version procedure ENDED at $TODAY\n";
  close LOGFILE;
} else {
  &PrintHelp;
}
close LOGFILE;
die();

#--------------------
# Dump of ace files 
# for each classes
#
sub DumpAce {
  my ($prefix,$database,$updatedir) = @_;
  foreach $currclass (@TotalClasses) {    
    print LOGFILE "Current class is $currclass\n";
    my $outfile = "$updatedir/"."$prefix"."$currclass".".$$".".ace";
    open (OUT,">$outfile") or die ("Could not open $outfile\n");
    print LOGFILE "Outfile will be $outfile\n";
    open2(READ,WRITE,$database) or die ("Could not open $database\n"); 
    $autocommand=<<EOF;
Query Find $currclass
Show -a
EOF
    print WRITE $autocommand;
    close WRITE;
    while (<READ>) {
      if ($_ =~ /\/\//) {next};
      if ($_ =~ /acedb/) {next};
      print OUT $_;
    }		    
    close READ;
    close OUT;
  }
}

#------------------------------------
# Keep a backup copy of the ace dumps
#
sub MoveAce {
  my ($olddir,$newdir,$updatedir) = @_;
# Erase OLD ace dump files
  system ("\\rm -f $olddir/*");
  print LOGFILE "\n** OLD Files removed **\n";
# Move ace dump files from NEW -> OLD
  @DIRLIST=($newdir);
  find sub {
    $oldfilename = $File::Find::name;
    if (!-d $oldfilename) {
      $newfilename = $oldfilename;
      $newfilename =~ s/$newdir/$olddir/;
      system("/bin/mv $oldfilename $newfilename");
      print LOGFILE "Moved $oldfilename to $newfilename\n";
    }
  },@DIRLIST;
  print LOGFILE "\n** PREVIOUS ace dumps moved in /old **\n";
# Move ace dump files from CURRENT -> NEW
  @DIRLIST=($updatedir);
  find sub {
    $c_filename = $File::Find::name;
    if ($c_filename =~ /($updatedir\/AUTO\_)/){
      $c_filename =~ s/$1//;
      $count{$c_filename}++;
#      push (@autofiles,$c_filename);
    }
    if ($c_filename =~ /($updatedir\/CGC\_)/){
      $c_filename =~ s/$1//;
      $count{$c_filename}++; 
#      push (@cgcfiles,$c_filename);
    }
  },@DIRLIST;
# Select only the ace dump files which are common between CGC and AUTO
  foreach $base (keys %count) {
    if ($count{$base}==2) {
      push @newfiles,$base;
    }
  }  
  foreach $file (@newfiles) { 
    my $autoseq="AUTO_"."$file";
    my $cgcseq="CGC_"."$file";
    print LOGFILE "Moving $autoseq to $newdir/$autoseq\n"; 
    system("/bin/mv $updatedir/$autoseq $newdir/$autoseq");
    print LOGFILE "Moving $cgcseq to $newdir/$cgcseq\n"; 
    system("/bin/mv $updatedir/$cgcseq $newdir/$cgcseq");
    push (@acemoved,$file);
  }
  print LOGFILE "\n** UPDATE Files moved in NEW **\n";
}

#--------------------------------------
# Produce diff files from the ace dumps
# 
sub DiffAce {
  print LOGFILE "ACEDIFFING @acemoved ..\n\n";
  my ($newdir,$diffdir,$acediff)=@_;
  system ("\\rm -f $diffdir/*.DIFF");
  print LOGFILE "\n** OLD DIFF files removed **\n";
  foreach $seq (@acemoved) {
    my $autoseq="$newdir/"."AUTO_"."$seq";
    my $cgcseq="$newdir/"."CGC_"."$seq";
    my $diffile="$diffdir/"."$seq".".DIFF";
    print LOGFILE "..Acediffing $seq ..\n";
    system("$acediff $cgcseq $autoseq > $diffile 2>>$LOGFILE");
    system ("/bin/compress $cgcseq");
    system ("/bin/compress $autoseq");
  } 
}

#-------------------------------------
# Produce the final raw data file
#
sub RawData {
  my $newdiffdir = shift @_;
  my $rawdatadir = "$newdiffdir"."/rawdata";
  $updfilename = "NULL";
  
# Retrieve the previous update file
  opendir (DIRHANDLE,"$rawdatadir");
  while (defined($filename = readdir (DIRHANDLE))) {
    if ($filename =~ /(update\.WS9\.4)(\-\d+)/) {    
      print "Found $filename\n";
      $vercount = $2;
      $oldupdfilename = "$rawdatadir/"."$filename";
      $filename =~ s/\.tar\.Z//;
      $updfilename = $filename;
      $updfilename =~ s/$vercount//;
      $vercount =~ s/\-//;
      $vercount++;
      $newupdatefile = "$rawdatadir/"."$updfilename"."-$vercount";
      $newupdfile = "$updfilename"."-$vercount";
    }
  }
  close DIRHANDLE;

# Retrieve the filenames to add to update file
  opendir (DIRHANDLE2,"$newdiffdir");
  while (defined ($filename = readdir (DIRHANDLE2))) {
    if ($filename =~ /DIFF/) {
      push @newfilenames,$filename;
   }
  }
  close DIRHANDLE2;

# Abort if no new filename or no update filename
  $noofiles = $#newfilenames + 1;
  if (($noofiles > 0)&&($updfilename !~ /NULL/)) {
    open (OUTPUT,">$newupdatefile");
    print OUTPUT "\/\/ acedb update 4 $vercount\n\n";
    close OUTPUT;
    unlink $oldupdfilename;
    foreach (@newfilenames) {
      chomp $_;
      $diffile = "$newdiffdir/"."$_";
      `cat $diffile >> $newupdatefile`;
      print LOGFILE "$diffile added to $newupdatefile\n";
    } 
  } else {
    print LOGFILE "** No update file produced - aborting ..\n";
    close LOGFILE;
    return 1;
  }
  
  # tar on ics-sparc1 because Solaris has the most generic tar function
  # rm any old tar files 
  # uncouple from logfile writing because there may be problem with rsh
  
  print LOGFILE "* Beginning remote tar on ics-sparc1 ..\n";
  my $remove1 = `\\rm $rawdatadir/*.tar.Z 2>/dev/null`;
#  $rs = `rsh ics-sparc1 \"cd $newdiffdir; tar -hcf $newupdfile.tar rawdata wspec pictures \"`;
  print LOGFILE "Made tar file $newupdfile.tar\n";
  print LOGFILE "Compressing relase files\n";
  system ("compress -f $newdiffdir/$newupdfile.tar");
# Finally remove the source file
  my $remove2 = `\\rm $newupdatefile 2>/dev/null`;
   `mv $newdiffdir/$newupdfile.tar.Z $rawdatadir/`;
}


#---------------------------------
# Transfers the compressed release 
# files from autoace to public ftp
#
sub TransferToFTP {
  my ($srcdir,$ftpdir) = @_;
  if (!-d $ftpdir) {
    system "mkdir $ftpdir";
  }
  @Zfiles=();
  @FTPLIST=($srcdir);
  find sub {
    $ftpfilename = $File::Find::name;
    if (!-d $ftpfilename) {
      if (($ftpfilename =~ /tar\.Z$/)||($ftpfilename =~ /\.gz$/)) {
	push (@Zfiles,$ftpfilename);
      }
      if (($ftpfilename =~ /composition/)||($ftpfilename =~ /totals/)) {
	push (@Zfiles,$ftpfilename);	
      }
    }
  },@FTPLIST;
  foreach (@Zfiles) {
    $src_file=$_;
    $tgt_file=$_;
    $tgt_file=~s/$srcdir/$ftpdir/;
    print LOGFILE "Copying file $src_file ..\n";
    `\/usr/bin/cp $src_file $tgt_file`;
    $O_SIZE = (stat($src_file))[7];
    $N_SIZE = (stat($tgt_file))[7];
    if ($O_SIZE != $N_SIZE) {
      print LOGFILE "*Error - file $src_file not transferred regularly - please check\n";
    } else {
      print LOGFILE "SRC: $O_SIZE   TGT: $N_SIZE\n";
    }
  }
}

#-----------------
# Close CGC server
#
sub ShutDownCGC {
  my $cgcace = shift;
  my $cgcommand=<<END;
shutdown now
END
    open2(READ,WRITE,$cgcace) or die ("Could not open $cgcace\n"); 
    print WRITE $cgcommand;
    close WRITE;
    while (<READ>) {
      if ($_ =~ /The server has disconnected/) {
	print LOGFILE "CGCace server disconnected\n";
      }
    }	    
    close READ;
}

#------------------------
# Get time coordinates
#
sub GetTime {
  @time = localtime();
  my ($SECS,$MINS,$HOURS,$DAY,$MONTH,$YEAR)=(localtime)[0,1,2,3,4,5];
  if ($time[1]=~/^\d{1,1}$/) {
    $time[1]="0"."$time[1]";
  }
  my $REALMONTH=$MONTH+1;
  my $REALYEAR=$YEAR+1900;
  my $TODAY = "$DAY $REALMONTH $REALYEAR at $HOURS:$MINS";
  return $TODAY;
}

#---------------------
# Print documentation
#
sub PrintHelp {
   exec ('perldoc',$0);
}

__DATA__
KeySet
LongText
Peptide
Sequence
Protein
DNA
Paper
Method
Map
Locus
Allele
2_point_data
Multi_pt_data
Clone
Contig
Motif
Keyword
View
Rearrangement
Gene_Class
Author
Laboratory
Strain
Pos_neg_data
Enzyme
Expr_Pattern
Grid
Species
Journal
Cell
Cell_group
Life_stage
TreeNode
Reconstruction
Database
Accession_number
Url
WWW_server
Pathway
PathwayDiagram
Metabolite
Picture
Tree
__END__

=pod

=head2   NAME - AcePublish

=head1 DESCRIPTION

AcePublish will either transfer the latest autoace version
to cgcace, including updating the .Z database and CHROMOSOME
files on the anonymous ftp repository, or dump acediff files
between current autoace version and current cgcace version,
to distribute to external users.

=head1 MANDATORY ARGUMENTS

=over 4

=item -n to transfer the latest autoace to cgcace and update ftp site

=item -v WS version number, mandatory with -n

=item -u to produce acediff files between autoace and cgcace

=back

=cut






