package Transcript;

use lib -e "/wormsrv2/scripts"  ? "/wormsrv2/scripts" : $ENV{'CVS_DIR'} ;
use Carp;
use Modules::SequenceObj;

@ISA = qw( SequenceObj );

sub new
  {
    my $class = shift;
    my $name = shift;
    my $exon_data = shift;
    my $strand = shift;

    my $self = SequenceObj->new($name, $exon_data, $strand);

    bless ( $self, $class );
    return $self;
  }

sub map_cDNA
  {
    my $self = shift;
    my $cdna = shift;

    # check for overlap
    if( $self->start > $cdna->end ) {
      return 0;
    }
    elsif( $cdna->start > $self->end ) {
      return 0;
    }
    else {
      #this must overlap - check exon matching
      $self->check_exon_match( $cdna );
      return 1;
    }
  }


sub check_exon_match 
  {
    my $self = shift;
    my $cdna = shift;

    #check if cDNA exon fits with gene model
    foreach my $cExonStart (keys %{$cdna->exon_data}) {
      my $gExonS;
      # do cDNA and gene share exon start position
      if ( $self->{'exons'}->{"$cExonStart"} ) {
	if ($self->{'exons'}->{"$cExonStart"} == $cdna->{'exons'}->{"$cExonStart"} ) {
	  #exact match
	  print "\tExact Match\n" if $verbose;
	}
	#is this final gene exon
	elsif ( $cExonStart == $self->last_exon->[0] ) {
	  if( $cdna->{'exons'}->{"$cExonStart"} > $self->last_exon->[1] ) {
	    print "\tMatch - last gene exon\n" if $verbose;
	  }
	  else {
	    print STDERR "MISS : cDNA splices in last gene exon\n" if $verbose;
	  }
	}
	# or final cDNA exon
	elsif ( $cExonStart == $cdna->last_exon->[0] ) {
	  # . . must terminate within gene exon
	  if ( $cdna->{'exons'}->{"$cExonStart"} > $self->{'exons'}->{"$cExonStart"} ) {
	    print STDERR "\tMISS - ",$cdna->name," $cExonStart => ",$cdna->{'exons'}->{$cExonStart}," extends over gene exon boundary\n" if $verbose;
	    return 0;
	  } else {
	    print "\tMatch - last cDNA exon\n" if $verbose;
	  }
	}
      }
      # do cDNA and gene share exon end position
      elsif ( ( $gExonS = $self->_exon_that_ends( $cdna->{'exons'}->{"$cExonStart"} ) and ($gExonS != 0) ) ) {
	#	# shared exon end
	
	if ( $gExonS == $self->first_exon->[0] ) { #is this the 1st gene exon 
	  if ( $cExonStart == $cdna->first_exon->[0] ) { # also cDNA start so always match
	    print "\tMatch - 1st exons overlap\n" if $verbose;
	  }
	  elsif ( $cExonStart < $self->first_exon->[0] ) { # cDNA exon overlap 1st gene exon
	    print "\tMatch - cDNA exon covers 1st gene exon\n" if $verbose;
	  }
	  else {
	    print STDERR "\tMISS - cDNA exon splices in gene exon\n" if $verbose;
	    print STDERR "\t\t",$cdna->name," $cExonStart => ",$cdna{'exons'}->{$cExonStart},"\n" if $verbose;
	    print STDERR "\t\t",$self->name," $gExonS => ",$self->{'exons'}->{$gExonS},"\n" if $verbose;
	    return 0;
	  }
	}
	# exon matched is not 1st of gene
	elsif ( ($cExonStart == $cdna->first_exon->[0] ) and # start of cDNA
		($cExonStart >$gExonS ) ) { # . . . is in gene exon
	  print"\tMatch - 1st exon of cDNA starts in exon of gene\n" if $verbose;
	} 
	else {
	  print STDERR "MISS - exon ",$cdna->name," : $cExonStart => ",$cdna{'exons'}->{$cExonStart}," overlaps start of gene exon : $gExonS => ",$self->{'exons'}->{$gExonS},"\n" if $verbose;
	  return 0;
	}
      }# cDNA_wholelyInExon
      elsif ( $self->_cDNA_wholelyInExon($cdna) ) {
	print "Match cDNA contained in exon\n" if $verbose;
      }
      # cDNA exon overlaps gene 1st exon start and terminate therein
      elsif( ( $cExonStart == $cdna->last_exon->[0] ) and #  last exon of cDNA
	     ( $cExonStart < $self->first_exon->[0] ) and 
	     ( $cdna->last_exon->[1] > $self->first_exon->[0] and $self->first_exon->[0] <$self->first_exon->[1] )
	   ) {
	print "\tcDNA final exon overlaps first exon of gene and end therein\n" if $verbose;
      }
      # cDNA exon starts in final gene exon and continues past end
      elsif( ($cdna->start > $self->last_exon->[0]) and 
	     ($cdna->start < $self->last_exon->[1]) and 
	     ($cdna->first_exon->[1] > $self->last_exon->[1] )
	   ) {
	print "final cDNA exon starts in final gene exon and continues past end\n" if $verbose;
      }
      else {
	# doesnt match
	print STDERR $cdna->name," doesnt match ",$self->name,"\n";
	return 0;
      }
    }
    $self->add_matching_cDNA( $cdna );
  }

sub _cDNA_wholelyInExon
  {
    my $self = shift;
    my $cdna = shift;

    foreach ( keys %{$self->exon_data} ) {
      if ( $cdna->start > $_ and $cdna->end < $self->{'exons'}->{$_} ) {
	return 1;
      }
    }
    return 0;
  }


sub add_matching_cDNA
  {
    my $self = shift;
    my $cdna = shift;
    print STDERR $cdna->name," matches ",$self->name,"\n";

    push( @{$self->{'matching_cdna'}},$cdna);
  }

sub report
  {
    my $self = shift;
    return unless $self->{'matching_cdna'};
    print STDERR "\nTranscript : \"", $self->name,"\"matches ",scalar @{$self->{'matching_cdna'}}," cDNAs\n";

    my %transcript = %{$self->exon_data};
    my @span = [( $self->start, $self->end) ];

    foreach my $cdna ( @{$self->{'matching_cdna'}} ) {
      print STDERR "Matching_cDNA \"",$cdna->name,"\" \n";

      foreach my $cdna_exon ( keys %{$cdna->exon_data} ) {
	# same as exists
	if( $transcript{$cdna_exon} = $cdna->exon_data->{$cdna_exon} ) {
	  next;
	}
	# start before what exists already
	elsif( $cdna_exon < $span[0] ) {
	  #. . and end before ie extend 5'UTR
	  if( $cdna->exon_data->{$cdna_exon} < $span[0] ) {
	    $transcript{$cdna} = $cdna->exon_data->{$cdna_exon};
	  }
	  else 
	    {
    }
  }









1;
