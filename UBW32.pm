#!/usr/bin/perl -w
#

package UBW32;

use strict;
use Device::SerialPort;
use Time::HiRes qw(usleep nanosleep);
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = "0.00a";
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(configure_pin set_pin print_pin enable_debug);
%EXPORT_TAGS = ( DEFAULT => [qw(&configure_pin &set_pin &print_pin &enable_debug)]);

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = {};
  $self->{PORT} = shift;
  $self->{pinconfigs} = {};
  $self->{port} = config_serport($self->{PORT}, shift, shift, shift, shift);
  $self->{dbg} = 0;
  bless($self, $class);           # but see below
  return $self;
}

sub enable_debug {
  my $self = shift;
  $self->{dbg} = shift;
}

sub config_serport {
  my $p = shift;
  my $db = shift || 8;
  my $br = shift || 9600;
  my $pa = shift || "none";
  my $sb = shift || 1;
  printf("Configuring %s\n", $p);
  my $tempport = Device::SerialPort->new($p);
  $tempport->databits($db);
  $tempport->baudrate($br);
  $tempport->parity($pa);
  $tempport->stopbits($sb);
  return $tempport;
}

sub print_pin {
  my $self = shift;
  my @cfg = @{$_[0]};
  return "${cfg[0]}${cfg[1]}";
}

sub validate_pin {
   my $group = shift;
   my $pin = shift;
   if( $group !~ /[ABCDEFG]/ ) {
     printf("Skipping pin %s%s: Invalid pingroup passed [%s] valid: A-G\n", $group, $pin, $group);
     return 1;
   } elsif( $pin > 15 || $pin < 0 ) {
     printf("Skipping pin %s%S: Invalid pin [%s] valid: 0-15\n", $group, $pin, $pin);
     return 1;
   }
   return 0;
}

sub configure_pin {
  my $self = shift;
  my $group = shift;
  my $pin = shift;
  my $dir = shift;
  my $result = "";
  my $dir_bit = ($dir eq "in") ? 1 :
                ($dir eq "out") ? 0 :
                -1;
  my $cmd = sprintf("PD,%s,%s,%s" , $group,$pin,$dir_bit);
  if($dir_bit < 0) {
     printf("Skipping pin %s%s: Invalid direction was passed [%s] valid: {in,out}\n", $group, $pin, $dir);
  } elsif( validate_pin($group,$pin) ){
  } else {
     if( !$self->{dbg} ) {
       $self->{port}->write("$cmd\n");
       $self->{port}->write_drain;
       usleep(10*1000);
       $result = $self->{port}->read(255);
     } else {
       $result = "OK";
     }
     if( $result !~ /OK/ ) {
        printf("Pin configuration failed: [%s][$cmd]\n", $result);
     } else {
       $self->{pinconfigs}{"$group$pin"}{direction} = $dir;
       $self->{pinconfigs}{"$group$pin"}{state} = "Unknown";
     }
  }
}

sub set_pin {
  my $self = shift;
  my $group = shift;
  my $pin = shift;
  my $value = shift;
  my $result = "";
  my $val_bit = ($value eq "low") ? 0 :
                ($value eq "high") ? 1 :
                -1;

  my $cmd = sprintf("PO,%s,%s,%s", $group,$pin,$val_bit);
  if( $val_bit < 0 ) {
     printf("Skipping pin %s%s: Invalid pin state was passed [%s] valid: {high,low}\n", $group, $pin, $value);
  } elsif( validate_pin($group,$pin) ){
  } elsif( $self->{pinconfigs}{"$group$pin"}{direction} ne "out" ) {
     printf("Skipping pin %s%s: Pin is set to input or no direction explicitly set\n", $group, $pin);
  } else {
    if(!$self->{dbg}){
      $self->{port}->write("$cmd\n");
      $self->{port}->write_drain;
      usleep(7.5*1000);
      $result = $self->{port}->read(255);
    } else {
      $result = "OK";
    }
    if( $result !~ /OK/ ) {
       printf("Pin state failed: [%s]\n", $result);
    } else {
       $self->{pinconfigs}{"$group$pin"}{state} = $value;
    }
  }
}

1;
