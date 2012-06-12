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

my %caps = (
   NC		=> 0,
   DigitalIn 	=> 1,
   DigitalOut 	=> 2,
   AnalogIn	=> 4,
   AnalogOut	=> 8, # Does this exist?
   SoftPWMIn	=> 16, #??
   SoftPWMOut	=> 32, 
   HardPWMIn	=> 64, #??
   HardPWMOut	=> 128,
   LED		=> 256,
   BUTTON	=> 512,
);

my %fw_caps = (
   1.62 => 1 + 2 + 4 + 32 + 128, # Are the capabilites HW Revision dependant?
);

my $StIO = 1 + 2 + 32;		# Normal Digital Pin, Can also Soft PWM
my $ADIO = $StIO + 4;		# Pin Can Analog In
my $PWIO = $StIO + 128;		# Pin can do HW PWM
my $SUIO = $StIO + 4 + 128;	# Pin can do everything.... does it exist?
my $LED  = $StIO + 256;		# Pin Has LED on it in hardware
my $BUTT = $StIO + 512;		# Pin Has button wired on pin to ground

my %pin_caps = (
# Group     0      1      2      3      4      5      6      7   
  A  => [$ADIO, $ADIO, $ADIO, $ADIO, $ADIO, $ADIO, $StIO, $StIO, 
#           8      9     10     11     12     13     14     15
         $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO,],
# Group     0      1      2      3      4      5      6      7   
  B  => [$StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, 
#           8      9     10     11     12     13     14     15
         $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO,],
# Group     0      1      2      3      4      5      6      7   
  C  => [$StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, 
#           8      9     10     11     12     13     14     15
         $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO,],
# Group     0      1      2      3      4      5      6      7   
  D  => [$PWIO, $PWIO, $PWIO, $PWIO, $PWIO, $StIO, $StIO, $StIO, 
#           8      9     10     11     12     13     14     15
         $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO,],
# Group     0      1      2      3      4      5      6      7   
  E  => [$LED , $LED , $LED , $LED , $StIO, $StIO, $BUTT, $BUTT, 
#           8      9     10     11     12     13     14     15
         $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO,],
# Group     0      1      2      3      4      5      6      7   
  F  => [$StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, 
#           8      9     10     11     12     13     14     15
         $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO,],
# Group     0      1      2      3      4      5      6      7   
  G  => [$StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, 
#           8      9     10     11     12     13     14     15
         $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO,],
);

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
   if( !$pin_caps{$group} ) {
     printf("Skipping pin %s%s: Invalid pingroup passed [%s] valid: A-G\n", $group, $pin, $group);
     return 1;
   } elsif( !$pin_caps{$group}[$pin] ) {
     printf("Skipping pin %s%s: Invalid pin [%s] valid: 0-15\n", $group, $pin, $pin);
     return 1;
   }
   return 0;
}

sub get_caps {
  my $group = shift;
  my $pin = shift;
  my @caps = [];
  foreach my $cap (keys %caps) {
    if($pin_caps{$group}[$pin] & $caps{$cap}) {
      push(@caps, $cap);
    }
  }
  return join(",", @caps);
}

sub get_cap_name {
  my $cap = shift;
  my @caps;
  foreach my $cap (keys %caps) {
    if($cap & $caps{$cap}) {
      push(@caps, $cap);
    }
  }
  return join(",", @caps);
}

sub cap_qty {
  my $testcaps = shift;
  my $count = 0;
  foreach my $cap (keys %caps) {
    if($testcaps & $caps{$cap}) {
      $count++;
    }
  }
  return $count;
}

sub configure_pin {
  my $self = shift;
  my $group = shift;
  my $pin = shift;
  my $cfg = shift;
  my $result = "";

  my $compat_map = $cfg eq "in" ? $caps{DigitalIn} :
		   $cfg eq "out" ? $caps{DigitalOut} :
			0;

  $cfg = $compat_map ? $compat_map : $cfg;
  
  if( validate_pin($group,$pin) ) {
  } elsif( $pin_caps{$group}[$pin] & $cfg == 0 ) {
     printf("Skipping pin %s%s: Invalid direction was passed [%s] valid: {%s}\n", 
            $group, $pin, get_cap_name($cfg), get_caps($group, $pin));
  } elsif( cap_qty($cfg) > 1 ) {
     printf("Skipping pin %s%s: Cannot set multiple states simultaneously [%s] valid: {%s}",
            $group, $pin, get_cap_name($cfg), get_caps($group, $pin));
  } else {
     my $cmd;
     if($cfg & $caps{DigitalIn})
     {
     	$cmd = sprintf("PD,%s,%s,%s" , $group,$pin,1);
     } elsif( $cfg & $caps{DigitalOut} ) {
     	$cmd = sprintf("PD,%s,%s,%s" , $group,$pin,0);
     } else {
     	$cmd = sprintf("PD,%s,%s,%s" , $group,$pin,$cfg);
     }
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
       $self->{pinconfigs}{"$group$pin"}{direction} = $cfg;
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
  } elsif( $self->{pinconfigs}{"$group$pin"}{direction} & $caps{DigitalOut} == 0 ) {
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
