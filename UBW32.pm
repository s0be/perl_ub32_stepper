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
@EXPORT_OK   = qw(configure_pin set_pin print_pin enable_debug %caps);
%EXPORT_TAGS = ( DEFAULT => [qw(&configure_pin &set_pin &print_pin &enable_debug)]);

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = {};
  $self->{PORT} = shift;
  $self->{pinconfigs} = {};
  $self->{used_spwm_channels} = (1);
  $self->{spwm_map} = {};
  $self->{port} = config_serport($self->{PORT}, shift, shift, shift, shift);
  $self->{dbg} = 0;
  bless($self, $class);           # but see below
  return $self;
}

sub enable_debug {
  my $self = shift;
  $self->{dbg} = shift;
}

our %caps = (
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
  A  => [$StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, 
#           8      9     10     11     12     13     14     15
         $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO, $StIO,],
# Group     0      1      2      3      4      5      6      7   
  B  => [$ADIO, $ADIO, $ADIO, $ADIO, $ADIO, $ADIO, $StIO, $StIO, 
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

my %analog_pins = (
  B => [ 1 , 2 , 4 , 8 , 16 , 32 ],
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
     return 0;
   } elsif( !$pin_caps{$group}[$pin] ) {
     printf("Skipping pin %s%s: Invalid pin [%s] valid: 0-15\n", $group, $pin, $pin);
     return 0;
   }
   return 1;
}

sub get_caps {
  my $group = shift;
  my $pin = shift;
  my @caps;
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
  foreach my $capname (keys %caps) {
    if($cap & $caps{$capname}) {
      push(@caps, $capname);
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

sub has_cap {
  my $group = shift;
  my $pin = shift;
  my $cap = shift;

  return $pin_caps{$group}[$pin] & $cap? 1 : 0;
}

sub analog_mask {
  my $group = shift;
  my $pin = shift;

  return $analog_pins{$group}[$pin];
}

sub find_softpwm_channel {
  my $self = shift;
  for (my $c = 1; $c <=64; $c++) {
    if(!$self->{used_spwm_channels}[$c]) {
      return $c;
    }
  }
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
  if($compat_map) {
    printf("Backwards compatable setup detected, mapping %s to %s\n", $cfg, get_cap_name($compat_map));
    $cfg = $compat_map;
  }
  
  if( !validate_pin($group,$pin) ) {
  } elsif( !has_cap($group, $pin, $cfg) ) {
     printf("Skipping pin %s%s: Invalid state was requested [%s] valid: {%s}\n", 
            $group, $pin, get_cap_name($cfg), get_caps($group, $pin));
  } elsif( cap_qty($cfg) > 1 ) {
     printf("Skipping pin %s%s: Cannot set multiple states simultaneously [%s] valid: {%s}",
            $group, $pin, get_cap_name($cfg), get_caps($group, $pin));
  } else {
     my $cmd;
     if($cfg & $caps{DigitalIn}) {
     	$cmd = sprintf("PD,%s,%s,%s" , $group,$pin,1);
     } elsif( $cfg & $caps{DigitalOut} ) {
     	$cmd = sprintf("PD,%s,%s,%s" , $group,$pin,0);
     } elsif( $cfg & $caps{AnalogIn} ) {
        $cmd = sprintf("CA,%s", analog_mask($group, $pin));
     } elsif( $cfg & $caps{SoftPWMOut} ) {
	my $free_channel = find_softpwm_channel($self);
        $self->{used_spwm_channels}[$free_channel] = 1;
        $self->{spwm_map}{$group}[$pin] = $free_channel;
	# This assumes that 0 is not a valid spwm channel to configure, and 64 is the 
	# maximum TOTAL number of spwm channels available.
        my $count = $#{$self->{used_spwm_channels}} ;
	if($count > 64) {
          printf("Too many Software PWM Channels Configured: [%s] max: [64]\n", $count);
	  return 1;
	}
     	$cmd = sprintf("PC,4,%s\nPC,2,%s,%s,%s",$count,$free_channel,$group,$pin);
     } elsif( $cfg & $caps{HardPWMOut} ) {
       #Stupidly assuming a pin must be set to Digital Output to PWM
       $cmd = sprintf("PD,%s,%s,%s" , $group,$pin,0);
     } else {
       printf("This shouldn't happen(Using an old library with code written for new module?).  Please report: [%s][%s][%s]\n",$group,$pin,$cfg);
       return 1;
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
       printf("Pin %s%s configured as %s\n", $group, $pin, get_cap_name($cfg));
       $self->{pinconfigs}{$group}[$pin]{mode} = $cfg;
       $self->{pinconfigs}{$group}[$pin]{state} = "Unknown";
       return 0;
     }
  }
  return 1;
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
  } elsif( !validate_pin($group,$pin) ){
  } elsif( $self->{pinconfigs}{$group}[$pin]{mode} != $caps{DigitalOut} ) {
     printf("Skipping pin %s%s: Pin is set to input or no direction explicitly set[%s]\n",
            $group, $pin, get_cap_name($self->{pinconfigs}{$group}[$pin]{mode}));
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
       $self->{pinconfigs}{$group}[$pin]{state} = $value;
    }
  }
}

1;
