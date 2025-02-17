#!/bin/env perl
#
# script to create the JSON for 
#   https://github.com/alliance-genome/agr_schemas/tree/release-1.0.1.1/ingest/htp
# based on: 
#   https://docs.google.com/spreadsheets/d/1H7bzMJVj6KevZHDGp61tCCdRo8ubHHzEKWaYu_7gn-w

use strict;
use Storable;
use Getopt::Long;
use Ace;
use JSON;
use Storable qw(dclone);

use lib $ENV{CVS_DIR};
use Wormbase;
use Modules::AGR;

my ($debug, $test, $verbose, $store, $acedbpath, $outfile,$ws_version,$outFdata,$wb_to_uberon_file);
GetOptions (
  'debug=s'     => \$debug,
  'test'        => \$test,
  'verbose'     => \$verbose,
  'store:s'     => \$store,
  'database:s'  => \$acedbpath,
  'samplefile:s'=> \$outfile,
  'datasetfile:s'=> \$outFdata,
  'wsversion=s' => \$ws_version,
  'wb2uberon=s' => \$wb_to_uberon_file,
)||die("unknown command line option: $@\n");

my $wormbase;
if ( $store ) {
  $wormbase = retrieve( $store ) or croak("Can't restore wormbase from $store\n");
} else {
  $wormbase = Wormbase->new( -debug   => $debug,
                             -test    => $test,
      );
}

my $tace = $wormbase->tace;
my $date = AGR::get_rfc_date();

$acedbpath  ||= $wormbase->autoace;
$ws_version ||= $wormbase->get_wormbase_version_name;

my $db = Ace->connect(-path => $acedbpath, -program => $tace) or die('Connection failure: '. Ace->error);

my @htps; # high troughput samples
my @htpd; # high thruput datasets

my $assembly = fetch_assembly($db,$wormbase);


my %htp; # to uniqueify it
my %uberon=%{read_uberron($wb_to_uberon_file)};

# RNASeq
my $it = $db->fetch_many(-query => 'find Analysis RNASeq_Study*;Species_in_analysis="Caenorhabditis elegans"')||die(Ace->error);
while (my $analysis = $it->next){

	my @p = $analysis->Reference;
	my @papers = map {get_paper($_)} @p;

	# sample
	foreach my $subproject ($analysis->Subproject){
	        next unless $subproject->Species_in_analysis eq 'Caenorhabditis elegans';
		my %json_obj;
		my $sample=$subproject->Sample;
        	my $datasetId="WB:${\$subproject->Project->name}";

		$json_obj{sampleId} = {
			primaryId => "WB:$subproject",
		}; # required
		$json_obj{sampleTitle} = $subproject->Title->name;
		$json_obj{sampleType} = 'OBI:0000895'; # total RNA extract
		$json_obj{assayType} = 'MMO:0000659'; # RNA-seq assay
		$json_obj{taxonId} = 'NCBITaxon:' . $wormbase->ncbi_tax_id;
		$json_obj{datasetIds} = [$datasetId];
		$json_obj{sex}=lc($sample->Sex->name) if $sample->Sex;

		sampleAge(\%json_obj,$sample) if $sample->Life_stage;
		sampleLocation(\%json_obj,$sample) if $sample->Tissue;

		$json_obj{assayType}='MMO:0000659'; # RNA-seq assay
		$json_obj{assemblyVersions}=[$assembly];
		push @htps,\%json_obj;

		# dataset
		
		# that will need more timeformat fiddling
		$db->timestamps(1);
                my $timestamp = $subproject->Project->timestamp;
		$timestamp=~s/_/T/;
		$timestamp=~s/_\w+/\+01:00/;
		$db->timestamps(0);
	
		my %json2_obj;
		$json2_obj{datasetId}= {primaryId => $datasetId,
					preferredCrossReference => ,{id =>$datasetId,pages => ['htp/dataset']}
		}; # required
		$json2_obj{publications} = \@papers if @papers;
		$json2_obj{dateAssigned} = $timestamp; #required
		$json2_obj{title} = ($analysis->Title->name ||"$analysis"); #required
		$json2_obj{summary} = $analysis->Description->name if $analysis->Description;
		$json2_obj{categoryTags}=['unclassified'];
		push @htpd,\%json2_obj unless $htp{$datasetId};
		$htp{$datasetId}=1;
	}
}

# MMO:0000659 - RNA-seq assay
# MMO:0000649 - microarray
# MMO:0000648 - transcript array
# MMO:0000664 - proteomic profiling
# MMO:0000666 - high throughput proteomic profiling
# MMO:0000000 - measurement method



# OBI:0000895 - total RNA extract
# OBI:0000869 - polyA RNA extract
# OBI:0000880 - RNA extract
# OBI:0000862 - nuclear RNA extract
# OBI:0000423 - extract
# OBI:0000876 - cytoplasmic RNA extract
# OBI:0002573 - polyA depleted RNA extract

# we can't submit microarrays without dataset, as the datasetId is required

# micro arrays - single channel

$it = $db->fetch_many(-query => 'find Microarray_experiment;Microarray_sample')||die(Ace->error);
while (my $array = $it->next){

	# dataset
	my %json2_obj;

	my @p = $array->Reference;
	my @papers = map {get_paper($_)} @p;

#        my $datasetId= 'WB:'.$p[0].'.ce.mr.csv';
	my $datasetId = {primaryId => 'WB:' . $array->name};

	my @papers = map {get_paper($_)} @p;
	$json2_obj{datasetId} = $datasetId; # required
	$json2_obj{publications} = \@papers if @papers;;
	$json2_obj{categoryTags}=['unclassified'];
	$json2_obj{numChannels}=1;
	$json2_obj{title} = $array->name;

	$db->timestamps(1);
	my $timestamp = $array->timestamp;
	$timestamp=~s/_/T/;
	$timestamp=~s/_\w+/\+01:00/;
	$db->timestamps(0);
	$json2_obj{dateAssigned} = $timestamp;
	

	push @htpd,\%json2_obj unless $htp{$datasetId};
	$htp{$datasetId}=1;

	# sample
	my %json_obj;
	my $sample=$array->Microarray_sample;
	$json_obj{sampleId} = {
		primaryId => "WB:$sample",
		secondaryId => ["WB:${\$array->name}"],
	};
	$json_obj{sampleTitle} = "WB:$sample";
	$json_obj{sampleType} = 'OBI:0000880'; # RNA extract
	

	$json_obj{taxonId} = 'NCBITaxon:' . $wormbase->ncbi_tax_id;
	$json_obj{datasetIds} = ['WB:' . $array->name];
	$json_obj{sex}=lc($sample->Sex->name) if $sample->Sex;

	sampleAge(\%json_obj,$sample) if ($sample->Life_stage);
	sampleLocation(\%json_obj,$sample) if ($sample->Tissue);

	$json_obj{assayType}='MMO:0000649'; # micro array
	$json_obj{assemblyVersions}=[$assembly];
	$json_obj{microarraySampleDetails} = {channelId => "WB:$sample", channelNum => 1};
	push @htps,\%json_obj;

}

# micro arrays - dual channel
$it = $db->fetch_many(-query => 'find Microarray_experiment;Sample_A;Sample_B')||die(Ace->error);
while (my $array = $it->next){

	# dataset
	my %json2_obj;
	my @p = $array->Reference;
	my @papers = map {get_paper($_)} @p;
#       my $datasetId= 'WB:'.$p[0].'.ce.mr.csv';
	my $datasetId = {primaryId => 'WB:' . $array->name};
	my @papers = map {get_paper($_)} @p;
	$json2_obj{datasetId} = $datasetId; # required
	$json2_obj{publications} = \@papers if @papers;;
	$json2_obj{categoryTags}=['unclassified'];
	$json2_obj{numChannels}=2;
	$json2_obj{title} = $array->name;

	$db->timestamps(1);
	my $timestamp = $array->timestamp;
	$timestamp=~s/_/T/;
	$timestamp=~s/_\w+/\+01:00/;
	$db->timestamps(0);
	$json2_obj{dateAssigned} = $timestamp;

	push @htpd,\%json2_obj unless $htp{$datasetId};
	$htp{$datasetId}=1;

	# sample
	my @samples=($array->Sample_A , $array->Sample_B);
	my $n=1;
	foreach my $s(@samples){
		my %json_obj;
		my $suffix = ($n==1) ? 'A' : 'B'; # for the datasets

		$json_obj{sampleTitle} = "WB:$s:$suffix";
		$json_obj{sampleType} = 'OBI:0000880'; # RNA extract
		$json_obj{sampleId} = {
		    primaryId => "WB:$s",
		    secondaryId => ["WB:${\$array->name}"],
		};

		$json_obj{taxonId} = 'NCBITaxon:' . $wormbase->ncbi_tax_id;
		$json_obj{datasetIds} = ['WB:' . $array->name];
		$json_obj{sex}=$s->Sex->name if $s->Sex;

                sampleAge(\%json_obj,$s) if $s->Life_stage;
		sampleLocation(\%json_obj,$s) if $s->Tissue;

		$json_obj{assayType}='MMO:0000649'; # micro array
		$json_obj{assemblyVersions}=[$assembly];
		$json_obj{microarraySampleDetails} = {channelId => "WB:$s:$suffix", channelNum => $n};
		push @htps,\%json_obj;

		$n++;
	}
}


################################################

print_json(\@htps,$outfile);
print_json(\@htpd,$outFdata);

$db->close;


####################################
# helper functions

# will change the hashref, so no return

sub sampleAge{
	my ($jsonRef,$sample)=@_;

	my $ls=$sample->Life_stage;

	return unless $ls && $ls->Public_name;

	$jsonRef->{sampleAge}={stage => { stageTermId => 'WB:'.$ls->name,
		                          stageName => $ls->Public_name->name ,
					  stageUberonSlimTerm => {uberonTerm => ((keys %{$uberon{$ls->name}})[0]||'post embryonic, pre-adult')},
				        }
	};
}

sub sampleLocation{
	my ($jsonRef,$sample)=@_;
	$jsonRef->{sampleLocations}=[];
	map {push @{$jsonRef->{sampleLocations}},
				{anatomicalStructureTermId => "WB:$_",
				 anatomicalStructureUberonSlimTermIds => [{uberonTerm =>((keys %{$uberon{$_->name}})[0] || 'Other')}],
				 whereExpressedStatement => ($_->Term->name || 'C.elegans Cell and Anatomy'),
			        }
  	} $sample->Tissue;
}

sub read_uberron{
	my ($file) = @_;
        my %wb2u;
	my $fh = IO::File->new($file);
	while (<$fh>){
          if (/^(\S+)\s+(\S+)/){
    		my $uberon = $1;
		my @list = split(/,/, $2);
    		foreach my $item (@list) {
      		  $wb2u{$item}->{"$uberon"} = 1;
		}
	  }
	}
	$wb2u{'WBbt:0000100'}->{Other} = 1;
	return \%wb2u;
}

sub print_json{
	my ($data,$file) = @_;
	print STDERR "printing $file\n";
	my $completeData = {
	  metaData => AGR::get_file_metadata_json( (defined $ws_version) ? $ws_version : $wormbase->get_wormbase_version_name(), $date ),
	  data     => $data,
	};
        my $fh;
	if ($file) {
	  open $fh, ">$file" or die "Could not open $outfile for writing\n";
	} else {
	  $fh = \*STDOUT;
	}

	my $json_obj = JSON->new;
	print $fh $json_obj->allow_nonref->canonical->pretty->encode($completeData);
}

###########
sub get_paper {
  my ($wb_paper) = @_;

  my $json_paper = {};

  my $pmid;
  foreach my $db ($wb_paper->Database) {
    if ($db->name eq 'MEDLINE') {
      $pmid = $db->right->right->name;
      last;
    }
  }
  $json_paper->{publicationId} = $pmid ? "PMID:$pmid" : "WB:$wb_paper";
  $json_paper->{crossReference} = {id =>"WB:$wb_paper",pages => ['reference']};

  return $json_paper;
}
###########

sub fetch_assembly{
	my ($db,$wormbase) = @_;
	# get the assembly name for the canonical bioproject
	my $assembly_name;
  
	my $species_obj = $db->fetch(-class => 'Species', -name => $wormbase->full_name);
	my @seq_col = $species_obj->at('Assembly');
        
	foreach my $seq_col_name (@seq_col) {
		my $bioproj;
		my $seq_col = $seq_col_name->fetch;
		my $this_assembly_name = $seq_col->Name;

		my @db = $seq_col->at('Origin.DB_info.Database');
		foreach my $db (@db) {
       			$bioproj = $db->right->right->name if ($db->name eq 'NCBI_BioProject');
		}
    
		if (defined $bioproj and $wormbase->ncbi_bioproject eq $bioproj) {
			$assembly_name = $this_assembly_name->name;
			last;
		}
        }
    
	if (not defined $assembly_name) {
	    die "Could not find name of current assembly for " . $wormbase->species() . "\n";
	}
        return $assembly_name;
}
