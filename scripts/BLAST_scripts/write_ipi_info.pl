#!/usr/local/bin/perl5.6.1

use strict;
use Getopt::Long;
use DB_File;

my $new;
GetOptions ( "new" => \$new );

my $wormpipe_dump = "/acari/work2a/wormpipe/dumps";

my $acc2db = "$wormpipe_dump/acc2db.dbm";
my $desc = "$wormpipe_dump/desc.dbm";
my $peptide = "$wormpipe_dump/peptide.dbm";
my $database = "$wormpipe_dump/databases.dbm";
my $list = "$wormpipe_dump/ipi_hits_list";
my $output = "$wormpipe_dump/ipi_hits.ace";

unless (-s "$acc2db" and -s "$desc"  and -s "$peptide") {
  die "problem with the dbm files - expecting :\n$acc2db\n$desc\n$peptide\n\n";
}

# These databases are written by parse_SWTREns_proteins.pl whenever a new data set is used
dbmopen my %ACC2DB, "$acc2db", 0666 or die "cannot open $acc2db\n";
dbmopen my %DESC, "$desc", 0666 or die "cannot open DBM file $desc\n";
dbmopen my %PEPTIDE, "$peptide", 0666 or die "cant open DBM file $peptide\n";
dbmopen my %DATABASE, "$database", 0666 or die "cant open DBM file $database\n";

# These are a couple of helper data sets to add in swissprot ids and SWALL / ENSEMBL gene names

my %swiss_id2gene;
my %acc2id;
&getSwissGeneName(\%swiss_id2gene, \%acc2id);

my %ENSpep_gene;  
&makeENSgenes( \%ENSpep_gene);

# This list is of the proteins to dump - generated by Dump_new_prot_only.pl during the dumping of similarity data
open (LIST, "<$list") or die "cant open $list\n";
open (ACE, ">$output") or die "cant open $output\n";

# Description goes in "Title" field for old style model 
my $title_desc = "Description";
$title_desc = "Title" unless $new;

while (<LIST>) {
  chomp;
  my $id = $_;
  my $prefix = $ACC2DB{$id};
  if( $prefix ) {
    print ACE "\nProtein : \"$prefix:$id\"\n";
    print ACE "Peptide \"$prefix:$id\"\n";
    print ACE "$title_desc \"$DESC{$id}\"\n" if $DESC{$id};
    print ACE "Species \"Homo sapiens\"\n";
  }
  else {
    print "no prefix for $id\n";
  }
  
  # write database lines
  my @databases = split (/\s+/,$DATABASE{$id}) if ( $DATABASE{$id} );

  # this is for new protein model

  #SwissProt_ID
  #SwissProt_Acc
  #TrEMBL_Acc
  #FlyBase_gn
  #Gadfly_ID
  #SGD_systematic
  #SGDID
  #ENSEMBL_geneID
  #ENSEMBL_proteinID
  #WORMPEP_ID 

  if ($new) {
    foreach (@databases) {
      my ($DB,$ID) = split(/:/, $_);
      if( "$DB" eq "ENSEMBL" ){
      print ACE "Database ENSEMBL ENSEMBL_proteinID $ID\n";
      print ACE "Database ENSEMBL ENSEMBL_geneID $ENSpep_gene{$ID}\n" if $ENSpep_gene{$ID};
      }
      elsif( "$DB" eq "SWISS-PROT" ){ 
	my $othername = $acc2id{$ID} if $acc2id{$ID};
	print ACE "Database SwissProt SwissProt_Acc $ID\n";
	print ACE "Database SwissProt SwissProt_ID $acc2id{$ID}\n" if $acc2id{$ID};
	print ACE "Gene_name \"$swiss_id2gene{$othername}\"\n" if $swiss_id2gene{$othername};
      }
      elsif( "$DB" eq "TREMBL" ){
	print ACE "Database TREMBL TrEMBL_Acc $ID\n";
      }
    }
  }

  # This is old protein model 
  else {
    foreach (@databases) {
      my ($DB,$ID) = split(/:/, $_);
      my $othername = $ID;
      if( "$DB" eq "ENSEMBL" ){
	$othername = $ENSpep_gene{$ID} if $ENSpep_gene{$ID};
      }
      elsif( "$DB" eq "SWISS-PROT" ){ 
	$othername = $acc2id{$ID} if $acc2id{$ID};
	print ACE "Other_name \"$swiss_id2gene{$othername}\"\n" if $swiss_id2gene{$othername};
      }
      
      print ACE "Database $DB $othername $ID\n";
    }
  }
  # This is the same for each
  print ACE "\nPeptide : \"$prefix:$id\"\n";
  print ACE "$PEPTIDE{$id}\n";
  
}

dbmclose %ACC2DB;
dbmclose %DESC;
dbmclose %PEPTIDE;
dbmclose %DATABASE;

exit(0);

sub getSwissGeneName
  {
    my $s2g = shift;
    my $a2i = shift;
    open (GETZ, "/usr/local/pubseq/bin/getz -f \"ID PrimAccNumber DBxref GeneName\" \"[swissprot-NCBI_TaxId#9606:9606]\" | ");
    my ($id, $acn, $gene, $backup_gene);
    my %counts;
    while (<GETZ>) {
      #print $_;
      chomp;
      if( /^ID\s+(\S+)/ ) {
	# before we move on to next protein check if the previous one received a gene name
	# if not use $backup_gene from the GN line rather than the Genew one
	unless( $$s2g{$id} ) {
	  if( $backup_gene ) {
	    $$s2g{$id} = $backup_gene;
	  }
	  else {
	    print "cant find a gene for $id\n";
	  }
	}
	undef $backup_gene;

	$id = $1;
	$counts{ids}++;
      }
      elsif( /^AC\s+(\S+) /) {
	$acn = $1;
	$acn =~ s/;//g;
	$$a2i{"$acn"} = $id; 
	$counts{acn}++;
      }
      elsif( (/GN\s+(\S+)[\s+\.]$/) || (/GN\s+(\S+)/ )){
	$backup_gene = $1;
      }
      elsif( /DR\s+Genew;\s+\w+:\d+;\s+(\w+)/ ) {
	    # DR   Genew; HGNC:989; BCL10
	$gene = $1;
	$$s2g{$id} = $gene;
	$counts{genes}++;
      }
    }
    foreach (keys %$s2g ) {
      print "ERROR \t\t$_\n" unless $$s2g{$_};
    }
    foreach (keys %counts) {
      print "$_ $counts{$_}\n";
    }
  }

sub makeENSgenes 
  {
    my $p2g = shift;
    open (ENS, "/usr/local/pubseq/bin/getz -f \"ID Gene\" \"[ensemblpep_human-ID:*]\" | ");

    #>ENSP00000217378 Gene:ENSG00000101397 Clone:AL049651 Contig:AL049651.2.1.97912 Chr:20 Basepair:23016474 Status:known
    while (<ENS>) {
      />(ENSP\d+) Gene:(ENSG\d+)/;
      $$p2g{$1} = $2;
    }
  }
