#!/usr/local/bin/perl5.6.0 -w
#
# agp2dna.pl
# dl1 020126
#
# Reconstructs chromosome DNA consensus file from the agp file.
# Each clone segment of sequence is checked from the EMBL
# entry (getz call) and the acedb derived DNA file.


$|=1;
use Getopt::Std;
use strict;
use vars qw ($seq_len $sv_acc $sv_ver $opt_d $opt_h $opt_s);
use lib "/wormsrv2/scripts/";
use Wormbase;

 ##############################
 # Script variables (run)     #
 ##############################

my $maintainers = "All";
my $rundate     = `date +%y%m%d`;   chomp $rundate;
my $runtime     = `date +%H:%M:%S`; chomp $runtime;
#my $version     = &get_cvs_version("$0");

my $dnadir = "/wormsrv2/autoace/CHROMOSOMES";
my $logdir = "/wormsrv2/autoace/yellow_brick_road";

my @gff_files = ('I','II','III','IV','V','X');

 ########################################
 # command-line options                 #
 ########################################

getopts ("hds:");
&usage(0) if ($opt_h);
my $debug = $opt_d;

# short-cut for developer
($maintainers = "dl1\@sanger.ac.uk") if ($debug);

# single chromosome mode
if ($opt_s) {
    @gff_files = ();
    &usage(5) unless (($opt_s eq "I") || ($opt_s eq "II") || ($opt_s eq "III") || ($opt_s eq "IV") || ($opt_s eq "V") || ($opt_s eq "X"));
    push (@gff_files, $opt_s);
}

 ########################################
 # Loop over each chromosome            # 
 ########################################

foreach my $chromosome (@gff_files) {
    
    # reset sequence strings (prevents concatenation across chromosomes)
    my $wormbase_seq = "";
    my $seq_con="";
    
    open (DNA, "<$dnadir/CHROMOSOME_$chromosome.dna") || &usage(1);
    while (<DNA>) {
	chomp;
	next if (/^>/);
	$wormbase_seq .= $_;
    }
    close DNA;
    
    # variables used in agp file loop
    my ($acc,$sv,$seq_ndb,$from,$to,$span,$start,$new_seq);
    my ($EMBL_acc,$EMBL_sv,$EMBL_seq,$EMBL_slice);
    my ($wormbase_slice,$wormbase_len,$agp_len);
      
    open (LOG, ">$logdir/CHROMOSOME_$chromosome.agp_seq.log") || &usage(3);
    open (AGP, "<$logdir/CHROMOSOME_$chromosome.agp") || &usage(2);
    while (<AGP>) {
	($acc,$sv,$seq_ndb,$from,$to,$span,$start,$new_seq) = "";
	my @f = split (/\s+/);
	
	# do block if not a gap
	unless ($f[4] eq "N") {
	    ($acc,$sv) = split (/\./,$f[5]);
	    $from  = $f[6] ;                 # sequence coords to string slice
	    $to    = $f[7] ;                 # sequence coords to string slice
	    $start = $f[6] - 1;
	    $span  = $f[7] - $f[6] + 1;
	    
	    # fetch the EMBL entry
	    ($EMBL_acc,$EMBL_sv,$EMBL_seq,$EMBL_slice) = "" ;
	    ($EMBL_acc,$EMBL_sv,$EMBL_seq) = &rubbish($acc);
	    $EMBL_slice = substr($EMBL_seq,$start,$span);
	    
	    # wrong orientation handling
	    if ($f[8] eq "-") {
		$EMBL_slice = substr($EMBL_seq,-$span);
		$EMBL_slice = &DNA_string_reverse($EMBL_slice);
	    }
	    
	    # check against WormBase sequence
	    $wormbase_slice = substr($wormbase_seq,($f[1]-1),$span);
	    $wormbase_len   = length ($wormbase_slice);
	    $agp_len        = length ($EMBL_slice);

	    # print log line
	    printf LOG "[%8d : %8d] %8s => Adding %6d bp from position %8d to %8d from version $EMBL_sv\n", $f[1],$f[2],$acc,$span,$from,$to;

	    # add to consensus sequence
	    $seq_con .= $EMBL_slice;
	    
	    # Sequence_version difference
	    if ($sv =! $EMBL_sv) {
		print LOG "ERROR: Discrepent sequence version for $acc [ACEDB:$sv <=> EMBL:$EMBL_sv\n";
	    }
	    
	    # Sequence length difference
	    if (length ($EMBL_slice) != $span) {
		print LOG "ERROR: Discrepent no. of bases added for $acc [ACEDB:$span <=> EMBL:" . length ($EMBL_slice) . "\n";
	    }
	    
            # Sequence difference
	    if ($EMBL_slice ne $wormbase_slice) {
		print LOG "ERROR: you are not adding the same sequence for $acc\n"; 
		my ($count_a,$count_c,$count_g,$count_t,$count_n)=&DNA_string_composition($wormbase_slice);
		print LOG "ERROR: WormBase [$acc] : A=$count_a C=$count_c G=$count_g T=$count_t N=$count_n\n";
		($count_a,$count_c,$count_g,$count_t,$count_n)=&DNA_string_composition($EMBL_slice);
		print LOG "ERROR: EMBL     [$acc] : A=$count_a C=$count_c G=$count_g T=$count_t N=$count_n\n";
	    }
	}
	# else insert gap 
	else {
	    # print log line
	    print LOG "[$f[1] : $f[2]] Adding $f[5] bp of padding characters (sequence gap)\n";
	    
	    # add to consensus sequence
	    $seq_con .= '-' x $f[5];
	}
    }
    close AGP;
    close LOG;

    # write reconstructed sequence to file
    open (DNA, ">$logdir/CHROMOSOME_${chromosome}.agp.seq") || &usage(4);
    print DNA  ">CHROMOSOME_$chromosome\n";
    print DNA  "$seq_con\n";
    close DNA;
}

 ########################################
 # hasta luego                          #
 ########################################

exit(0);

 ########################################
 # getz query accession for sequence    #
 ########################################

sub rubbish {
    
    my $acc = shift;
    my ($EMBL_acc,$EMBL_sv,$EMBL_seq);
    
    open (SEQUENCE, "getz -d -sf fasta -f \'seqversion\' \"[emblnew-acc:$acc] > [embl-acc:$acc]\" |");
    while (<SEQUENCE>) {
	chomp;
	if (/^SV\s+(\S+)\.(\d+)/) {
	    ($EMBL_acc,$EMBL_sv) = ($1,$2);
	    $EMBL_seq = "";
	    next;
	}
	next if (/^>/);
	$EMBL_seq .= $_;
    }
    close SEQUENCE;

    return($EMBL_acc,$EMBL_sv,$EMBL_seq);
}


 ########################################
 # Usage and errors                     #
 ########################################

sub usage {
    my $error = shift;
    if ($error == 1){ 
        # Error 01 - no DNA file to read
        print "No Chromosome DNA file available.\n";
        exit(1);
    }
    elsif ($error == 2){ 
        # Error 02 - no agp file to read
        print "No Chromosome agp file available.\n";
        exit(1);
    }
    elsif ($error == 3){ 
        # Error 03 - failed to open agp_seq.log file to write
        print "Failed to open *.agp_seq.log file. Aborting run.\n";
        exit(1);
    }
    elsif ($error == 4){ 
        # Error 04 - failed to open agp.seq file to write
        print "Failed to open *.agp.seq file. Aborting run.\n";
        exit(1);
    }
    elsif ($error == 5){ 
        # Error 05 - Single chromosome mode with invalid chromosome
        print "Single chromosome mode aborted. '$opt_s' is not a valid chromsome designation.\n";
        exit(1);
    }
    elsif ($error == 0) {
	# Normal help menu
	exec ('perldoc',$0);
    }

}

__END__

=pod

=head2 NAME - agp2dna.pl

=head1 USAGE:

=over 4

=item agp2dna.pl [-options]

=back

agp2dna.pl mandatory arguments:

=over 4

=item none

=back

agp2dna.pl optional arguments:

=over 4

=item -s [txt], Single chromosome mode. Valid options (I,II,III,IV,V and X)

=item -h, Help page

=item -d, Verbose/Debug mode

=back

=head1 RUN REQUIREMENTS:

agp2dna.pl requires a number of files:

CHROMOSOME_*.dna : DNA sequence for the chromosome [/wormsrv2/autoace/CHROMOSOMES/]

CHROMOSOME_*.agp : agp file for the chromosome [/wormsrv2/autoace/CHROMOSOMES/]

=head1 EXAMPLES:

=over 4

=item agp2dna.pl 

=back

Reconstructs the chromosome sequences for all chromsomes using agp files from /wormsrv2/autoace/CHROMOSOMES
and compares the sequence with the dna file in /wormsrv2/autoace/CHROMOSOMES. The reconstructed dna file
and log files can be found in /wormsrv2/autoace/yellow_brick_road

=over 4

=item agp2dna.pl -s I

=back

Reconstructs the chromosome sequences for chromsome I using agp file from /wormsrv2/autoace/CHROMOSOMES
and compares the sequence with the dna file in /wormsrv2/autoace/CHROMOSOMES. The reconstructed dna file
and log files can be found in /wormsrv2/autoace/yellow_brick_road


=head1 AUTHOR:

Daniel Lawson : Email dl1@sanger.ac.uk

=cut
