#!/usr/local/bin/perl5.6.1

# Marc Sohrmann (ms2@sanger.ac.uk)

# takes as input a swissprot or trembl .fasta file,
# and deletes all worm, fly, human and yesast entries
BEGIN {
    unshift (@INC , "/nfs/acari/wormpipe/scripts/BLAST_scripts");
}
my $wormpipe = glob("~wormpipe");
use strict;
use Getopt::Long;
use DB_File;
use GSI;

my ($swiss, $trembl, $debug, $database, $list, $old, $species);
# $old is for switch back to protein model
GetOptions (
	    "swiss"      => \$swiss,
	    "trembl"     => \$trembl,
	    "database:s" => \$database,
	    "list"       => \$list,
	    "old"        => \$old,
	    "debug"      => \$debug,
	    "species=s"  => \$species
	  );

my $wormpipe_dump = "/acari/work2a/wormpipe/dumps";
$wormpipe_dump .= "_test" if $debug;
my $output_swiss = "$wormpipe_dump/swissproteins.ace";
my $output_trembl = "$wormpipe_dump/tremblproteins.ace";
my $db_files = "/acari/work2a/wormpipe/swall_data";
my $swiss_list_txt = "$wormpipe_dump/swisslist.txt";
my $trembl_list_txt = "$wormpipe_dump/trembllist.txt";
my $blastx_file = "$wormpipe_dump/blastx_ensembl.ace";
my $blastp_file = "$wormpipe_dump/blastp_ensembl.ace";
my $ensembl_info_file = "$wormpipe_dump/ensembl_protein_info.ace";

my @blastp_databases = qw(worm_pep worm_brigpep);
my $blast_files = "$wormpipe_dump/*blastp.ace $wormpipe_dump/*blastx.ace ";
#foreach ( @blastp_databases ) {
#  $blast_files .= "$wormpipe_dump/$_/blastp/ACE/wublastp_slimtrembl.ace ";
#  $blast_files .= "$wormpipe_dump/$_/blastp/ACE/wublastp_slimswissprot.ace ";
#}
#if ( $species ) {
#  $output_swiss = "$wormpipe_dump/${species}_swissproteins.ace";
#  $output_trembl = "$wormpipe_dump/${species}_tremblproteins.ace";
#  $swiss_list_txt = "$wormpipe_dump/${species}_swisslist.txt";
#  $trembl_list_txt = "$wormpipe_dump/${species}_trembllist.txt";
#  $blastx_file = "";#$wormpipe_dump/${species}_blastx_ensembl.ace";
#  $blastp_file = "$wormpipe_dump/${species}_blastp_ensembl.ace";
#  $ensembl_info_file = "$wormpipe_dump/${species}_ensembl_protein_info.ace";
#}

# extract and write lists of which proteins have matches
unless ( $list ){
  open (DATA,"cat $blast_files |");
  my (%swisslist, %trembllist);
  while (<DATA>) {
    if (/Pep_homol\s+\"/) {
      if( /SW:(\S+)\"/ ) {
	$swisslist{$1} = 1;
      }
      elsif( /Pep_homol\s+\"TR:(\S+)\"/ ) {
	$trembllist{$1} = 1;
      }
    }
  }
  close DATA;
  
  open (SWISS,">$swiss_list_txt");
  open (TREMBL,">$trembl_list_txt");
  foreach (keys %swisslist) { print SWISS "$_\n"; }
  foreach (keys %trembllist) { print TREMBL "$_\n"; }
  
  close SWISS;
  close TREMBL;
}
# now extract info from dbm files and write ace files

my @lists_to_dump;
$db_files = "$database" if defined $database;  # can use other database files if desired

my %input2output;
$input2output{"$swiss_list_txt"}  = [ ("$output_swiss", "SwissProt", "SW", "$db_files/slimswissprot" ) ];
$input2output{"$trembl_list_txt"} = [ ("$output_trembl", "TrEMBL", "TR", "$db_files/slimtrembl" ) ];

my @lists_to_dump;
$db_files = "$database" if defined $database;  # can use other database files if desired

my %ORG;
my %DES;

unless ($swiss || $trembl) {
    die "usage -swiss for swissprot, -trembl for trembl, -database directory where .gsi database file is\n";
}

if ($swiss) {
  unless (-s "$db_files/swissprot2org") {
    die "swissprot2org not found or empty";
  }
  dbmopen %ORG, "$db_files/swissprot2org", 0666 or die "cannot open swissprot2org DBM file $db_files/swissprot2org";
  unless (-s "$db_files/swissprot2des") {
    die "swissprot2des not found or empty";
  }
  dbmopen %DES, "$db_files/swissprot2des", 0666 or die "cannot open swissprot2des DBM file $db_files/swissprot2des";
  &output_list($swiss_list_txt,$input2output{"$swiss_list_txt"});
  dbmclose %ORG;
  dbmclose %DES;
}

if ($trembl) {
  unless (-s "$db_files/trembl2org") {
    die "trembl2org not found or empty";
  }
  dbmopen %ORG, "$db_files/trembl2org", 0666 or die "cannot open trembl2org DBM file";
  unless (-s "$db_files/trembl2des") {
    die "trembl2des not found or empty";
  }
  dbmopen %DES, "$db_files/trembl2des", 0666 or die "cannot open trembl2des DBM file";
  push( @lists_to_dump,$trembl_list_txt);
  &output_list($trembl_list_txt,$input2output{"$trembl_list_txt"});
  dbmclose %ORG;
  dbmclose %DES;
}

system("cat $output_swiss $output_trembl > $ensembl_info_file");

exit(0);
    

sub output_list
  {
    my $list = shift;
    my $parameters = shift;
    my $db = $$parameters[1];
    my $fetch_db = $$parameters[3].".gsi";
    my $prefix = $$parameters[2];
    my $outfile = $$parameters[0];
    
    #used to be in fetch.pl
    ########################
    # open the GSI file
    GSI::openGSI ("$fetch_db");
    ########################


    open (LIST,"<$list") or die "cant open input file $list\n";
    open (ACE, ">$outfile") or die "cant write to $outfile\n";
    while (<LIST>) {
      #	print;  # ID line 
      chomp;
      /^(\S+)/;

      my $id = $1;
      
      # access gsi database to get info about protein
      my ($file , $fmt , $offset) = GSI::getOffset ($id);
      unless( "$file" eq "-1" ) {
	open (DB , "$file") || die "cannot open db $file\n";
	seek (DB , $offset , 0);
	my $header = <DB>;
	chomp $header;
	my $seq = "";
	while ((my $line = <DB>) =~ /^[^\>]/) {
	  $seq .= "$line"."\n";
	}
	close DB;
	$seq =~ s/\n//g;
	
	$header =~ /^\S+\s+(\S+)/;
	my $accession = $1;
	
	if ($seq) {
	  print ACE "Protein : \"$prefix:$id\"\n";
	  print ACE "Peptide \"$prefix:$id\"\n";
	  print ACE "Species \"$ORG{$id}\"\n";
	  unless( $old ) {
	    print ACE "Description \"$DES{$id}\"\n";
	    if ("$prefix" eq "SW" ) {
	      print ACE "Database SwissProt SwissProt_ID $id\n";
	      print ACE "Database SwissProt SwissProt_AC $accession\n";
	    }
	    else {
	      print ACE "Database TREMBL TrEMBL_AC $id\n";
	    }
	  }
	  else {
	    # this is the old style - left for safety remove after WS104
	    print ACE "Title \"$DES{$id}\"\n";
	    print ACE  "Database \"$db\" \"$id\" \"$accession\"\n";
	  }

	  print ACE  "\n";
	  print ACE  "Peptide : \"$prefix:$id\"\n";
	  print ACE "$seq\n";
	  print ACE "\n";
	}
	else {
	  print "// Couldn't fetch sequence for $id\n\n";
	}
      }  
    }
  }


__END__

=pod

=head2   NAME - write.swiss_trembl.pl

=head1 USAGE

=over 4

=item write.swiss_trembl.pl [-options]

-swiss  get SwissProt entries

-trembl get TrEMBL  entries

-debug  read/write to different directory

-database specify a non-default .gsi directory to use

=back

This script creates ace files containing the details of any proteins that have blast matches.

The input list are simply a list of ID's of matching proteins.

The .gsi databases are written by fasta2gsi.pl -f /acari/work2a/wormpipe/swall_data/slimswissprot whenever the swissprot/trembl are updated.
