package Error::Show;

use 5.024000;
use strict;
use warnings;
use feature "say";
use Carp;
use POSIX;  #For _exit;
use IPC::Open3;
use Symbol 'gensym'; # vivify a separate handle for STDERR

#use Exporter qw<import>;
use base "Exporter";


our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} });

our @EXPORT = qw();


our $VERSION = 'v0.1.0';
use constant DEBUG=>0;


################################
# my $buffer="";               #
# open THITHER  ,">",\$buffer; #
################################

#
# A list of top level file paths or scalar refs to check for syntax errors
#
my @IINC;
sub context;

 
sub import {
  my $package=shift;
  my @caller=caller;
  my @options=@_;


  if($caller[2]){
    # 
    # A nonzero line means included in code, not from command line.
    #
    return;
  }

  # 
  # CLI Options include 

  my %options;

  my $clean=grep /clean/i, @options;
  my $splain=grep /splain/i, @options;
  my $do_warn=grep /warn/i, @options;

  my @warn=$do_warn?():"-MError::Show::Internal";


  #
  # 1. Command line argument activation ie -MError::Show
  #
  # Find out any extra lib paths used. To do this we:
  #
  # a. fork/exec a new perl process using the value of $^X. 
  # b. The new process dumps the @INC array to STDOUT
  # c. This process reads the output and stores in @IINC
  #
  # Only run it the first time its used
  # Is this the best way? Not sure. At least this way there is no argument
  # processing, perl process does it for us.
  #
  
  @IINC=map {chomp; $_} do {
    open my $fh, "-|", $^X . q| -E 'map print("$_\n"), @INC'| or die "$!";
    <$fh>;
  } unless @IINC;

  #
  # 2. Extract the extra include paths
  #
  # Built up the 'extra' array of any include paths not already listed 
  # from the STDOUT dumping above
  #
  my @extra=map  {("-I", $_)} grep {my $i=$_; !grep { $i eq $_} @IINC} @INC;



  # 
  # 3. Syntax checking the program
  #
  # Now we have the include paths sorted,
  # a. fork/exec again, this time with the -c switch for perl to check syntax
  # b. slurp STDERR from child process
  # c. execute the context routine to parse and show more source code context
  # d. print!
  # The proc

  local $/=undef;
  my $file=$0;

  #push @file, @ARGV;

  #my $runnable=not $^C;#$options{check};
  #for my $file(@file){
  die "Sorry, cannot Error::Show \"$file\"" unless -f $file;
  my @cmd= ($^X ,@warn, @extra, "-c",  $file);

    my $pid;
    my $result;
    eval {
      $pid=open3(my $chld_in, my $chld_out, my $chld_err = gensym, @cmd);
      $result=<$chld_err>;
      close $chld_in;
      close $chld_out;
      close $chld_err;
      wait;
    };
    if(!$pid and $@){
      die "Error::Show failed to syntax check";
    }


  # 
  # 4. Status code from child indicates success
  # When 0 this means syntax was ok. Otherwise error
  # Attempt to propogate code to exit status
  #
  my $code=$?>255? (0xFF & ~$?): $?;

  my $runnable=$?==0;
  #say "SYNTAX RUNNABLE: $runnable";

  my $status=context(splain=>$splain, clean=>$clean, error=>$result, program=>$file)."\n";

  if($^C){
    if($runnable){
      #only print status if we want warnings
      print STDERR $do_warn?$status: "$file syntax OK\n";

    }
    else{
      #Not runnable, thus  syntax error. Always print
      print STDERR $status;

    }
    POSIX::_exit $code;

  }
  else{
    #not checking, we want to run
    if($runnable){
      # don't bother with warnings

    }
    else{
      #Not runnable, thus  syntax error. Always print
      print STDERR $status;
      POSIX::_exit $code;
    }
  }
}


our %exception_adaptors;
$exception_adaptors{"Exception::Base"}=sub {

};

$exception_adaptors{"Exception::Class::Base"}=sub {
  #take an error
  my $e=shift;
};


sub process_ref_errror{
  #
  # This can only be a (single) runtime error
  #
  my $error=pop;
  my %opts=@_;
  my $ref=ref $error;


  my %entry;

  # 
  # TODO: 
  # Lookup handler code to process this type of error
  # 

  \%entry;

}

sub process_string_error{
  my $error=pop;
  my %opts=@_;

	my @error_lines;
  my @errors; 
  #my @entry;
  my %entry;
	if(defined $error){
    #local $_=$error;
		#Substitue with a line number relative to the start marker
		#Reported line numbers are 1 based, stored lines are 0 based
    #my $translation=$opts{translation};
    #my $start=$opts{start};
  
    my $i=0;
		for(split "\n", $error){
      if(/at (.*?) line (\d+)/){
        #
        # Group by file names
        #
        my $entry=$entry{$1}//=[];
        push @$entry, {file=>$1, line=>$2,message=>$_, sequence=>$i++};
      }
    }

    
    #return "$opts{program} syntax OK" if $opts{program} and !@error_lines;
    #@error_lines=(shift @error_lines);
	}
	else {
		#Assume a target line
    #push @error_lines, $opts{line}-1;
	}

  #Key is file name
  # value is a hash of filename,line number, perl error string and the sequence number

  \%entry;

}

sub text_output {
  my $info_ref=pop;
  my %opts=@_;
  my $total="";

  # Sort by sequence number 
  my @sorted_info= 
    sort { $a->{sequence} <=> $b->{sequence} } 
    map { $_->@* } values %$info_ref;

  # Process each of the errors in sequence
  for my $info (@sorted_info){
    unless(exists $info->{code_lines}){
      my @code;
      
      if($info->{file} =~ /\(eval \d+\)/){
        @code=split "\n", $opts{program}//"";
      }
      else {
        @code=split "\n", do {
          open my $fh, "<", $info->{file} or warn "Could not open file for reading: $info->{file}";
          local $/=undef;
          <$fh>;
        };
      }
      $info->{code_lines}=\@code;
    }

    my $min=$info->{line}-$opts{pre_lines};
    my $max=$info->{line}+$opts{post_lines};

    my $target= $info->{line};

    $min=$min<0 ? 0: $min;
    my $count=$info->{code_lines}->@*;
    $max=$max>=$count?$count:$max;

    #
    # format counter on the largest number to be expected
    #
    my $f_len=length("$max");

    my $out="$opts{indent}$info->{file}\n";
    
    my $indent=$opts{indent}//"";
    my $format="$indent%${f_len}d% 2s %s\n";
    my $mark="";

    #Change min and max to one based index
    $min++;
    #$max--;

    for my $l($min..$max){
      $mark="";

      #Perl line number is 1 based
      $mark="=>" if $l==$info->{line};

      #say $info->{code_lines}[$l-1];
      #say $l;
      #However our code lines are stored in a 0 based array
      $out.=sprintf $format, $l, $mark, $info->{code_lines}[$l-1];
    }
    $total.=$out;
    $total.=$info->{message}."\n" unless $opts{clean};

  }
  if($opts{splain}){
    $total=splain($total);
  }
  $total;
}


#Take an error string and attempt to contextualize it
#	context options_pairs, error string	
sub _context{
	#use feature ":all";
	DEBUG and say STDERR "IN context call";
  #my ($package, $file, $caller_line)=caller;
	# 
  # Error is set by single argument, key/value pair, or if no
  # argument $@ is used
  #
	my %opts=@_;
  my $error= $opts{error};

  #################################
  # if(@_==0){                    #
  #   $error=$@;                  #
  # }                             #
  # elsif(@_==1){                 #
  #   $error=shift;               #
  # }                             #
  # else {                        #
  #   %opts=@_;                   #
  #         $error= $opts{error}; #
  # }                             #
  #                               #
  #################################
  my $program;

  #	
  # Remaining arguments are to be key/value options
  #

  # 
  # Program is the original application file or string ref
  #
  $program=$opts{program};

  # 
  # If no program has been specifed yet, attempt to extract from the actual
  # error message.
  #
  #unless($program){



	$opts{start_mark}//=qr|.*|;	#regex which matches the start of the code 
	$opts{pre_lines}//=5;		#Number of lines to show before target line
	$opts{post_lines}//=5;		#Number of lines to show after target line
	$opts{offset_start}//=0;	#Offset past start to consider as min line
	$opts{offset_end}//=0;		#Offset before end to consider as max line
	$opts{translation}//=0;		#A static value added to the line numbering
	$opts{indent}//="";
	$opts{file}//="";

  # Get the all the info we need to process
  my $info_ref;
  if(defined($error) and ref($error) eq ""){
    #A string error. A normal string die/warn or compile time errors/warnings
    $info_ref=process_string_error %opts, $error;
    #say "infor ref ".join ", ", $info_ref;
  }
  else{
    #Some kind of object, converted into line and file hash
    $info_ref={$error->{file}=>[$error]};
  }
  
  my $output;
  $output=text_output %opts, $info_ref;
  
  #TODO:
  #
	$output;
  
}


#
# This only works with errors objects which captured a trace as a Devel::StackTrace object
#
my $msg= "Trace must be a ref to array of  {file=>.., line=>..} pairs";
sub context{
  my %opts;
  my $out;
  if(@_==0){
    $opts{error}=$@;
  }
  elsif(@_==1){
    $opts{error}=shift;
  }
  else {
    %opts=@_;
  }
  # Convert from supported exceptions classes to internal format
  use Scalar::Util;
  my $package=Scalar::Util::blessed $opts{error};
  if($package){
    no strict "refs";
    say "Package is: ", @{$package."::ISA"};
  }

  #Check for trace kv pair. If this is present. We ignore the error
  if(ref($opts{error}) eq "ARRAY"){

    # Iterate through the list
    my $_indent=$opts{indent}//="    ";
    my $current_indent="";

    my %_opts=%opts;
    for my $e ($opts{error}->@*) {
      if($e->{file} and $e->{line}){
        $e->{message}//="";
        $_opts{indent}=$current_indent;

        $_opts{error}=$e;
        $out.=_context %_opts;

        $current_indent.=$_indent;
      }
      else{
        die $msg;
      }
    }

  }
  else {
    #say "NOT AN ARRAY: ". join ", ", %opts;

    $out=_context %opts;
  }
  $out;
}

my ($chld_in, $chld_out, $chld_err);
my @cmd="splain";
my $pid;
sub splain {
  my $out;
  #Attempt to open splain process if it isn't already
  unless($pid){
    eval{
      $pid= open3($chld_in, $chld_out, $chld_err = gensym, @cmd);
      #$chld_in->autoflush(1);

    };
    if(!$pid and $@){
      warn "Error::Show Could not splain the results";
    }
  };

  #Attempt to write to the process and read from it
  eval {
    print $chld_in $_[0], "\n";;
    close $chld_in;
    $out=<$chld_out>;
    close $chld_out;
    close $chld_err;
  };

  if($@){
    $pid=undef;
    close $chld_in;
    close $chld_out;
    close $chld_err;
    warn "Error::Show Could not splain the results";
  }
  $out;
}

sub ecb_help {
  my $e=shift;
  {line=>$e->line, file=>$e->file, message=>"$e"};
}
sub ecb_trace_help {
  my $e=shift;
  \(map {{file=>$_->filename, line=>$_->line, message=>$e}} $e->trace->frames);
}
1;
__END__
