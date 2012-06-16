#!/usr/bin/perl
#

package UBW32;

use strict;
use warnings;
use Device::SerialPort;
use Time::HiRes qw(usleep nanosleep);
use Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION     = "0.00a";
@ISA         = qw(Exporter);
@EXPORT      = ();
@EXPORT_OK   = qw(configure_pin set_pin print_pin enable_debug %caps);
%EXPORT_TAGS = ( DEFAULT => [qw(&configure_pin &set_pin &print_pin &enable_debug)]);

our %caps = (
   NC		=> 0,
   DigitalIn 	=> 1 << 0,
   DigitalOut 	=> 1 << 1,
   AnalogIn	=> 1 << 2,
   AnalogOut	=> 1 << 3, # Does this exist?
   SoftPWMIn	=> 1 << 4, #??
   SoftPWMOut	=> 1 << 5, 
   HardPWMIn	=> 1 << 6, #??
   HardPWMOut	=> 1 << 7,
   LED		=> 1 << 8,
   BUTTON	=> 1 << 9,
   Unconfigured => 1 << 16,
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
# Pin:   0   1   2   3   4    5
  B => [ 1 , 2 , 4 , 8 , 16 , 32 ],
);

my %hwpwm_pins = (
# Pin:   0  1  2  3  4
  D => [ 1, 2 ,3, 4, 5],
);

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = {};
  $self->{PORT} = shift;
  $self->{pinconfigs} = {};
  $self->{msg} = sub {};
  foreach my $g ( qw(A B C D E F G)) {
    for( my $p = 0; $p <= 15; $p++ ) {
      $self->{pinconfigs}{$g}[$p]{mode} = $caps{Unconfigured};
      $self->{pinconfigs}{$g}[$p]{state} = undef;
    }
  }
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

sub set_msg_handler {
  my $self = shift;
  my $handler = shift;
  $self->{msg} = $handler;
}

sub config_serport {
  my $p = shift;
  my $db = shift || 8;
  my $br = shift || 9600;
  my $pa = shift || "none";
  my $sb = shift || 1;
  my $tempport = Device::SerialPort->new($p);
  if($tempport) {
    $tempport->databits($db);
    $tempport->baudrate($br);
    $tempport->parity($pa);
    $tempport->stopbits($sb);
    # It seems like we need to reset the analog inputs to use them as digital
    $tempport->write("CA,0\n");
    usleep(100 * 1000);
    # Also, "R" doesn't seem to reset hardware PWM channels...
    $tempport->write("PM,1,0\n");
    usleep(100 * 1000);
    $tempport->write("PM,2,0\n");
    usleep(100 * 1000);
    $tempport->write("PM,3,0\n");
    usleep(100 * 1000);
    $tempport->write("PM,4,0\n");
    usleep(100 * 1000);
    $tempport->write("PM,5,0\n");
    usleep(100 * 1000);
    $tempport->write("R\n");
    usleep(100 * 1000);
  }
  return $tempport;
}

sub print_pin {
  my $self = shift;
  my @cfg = @{$_[0]};
  return "${cfg[0]}${cfg[1]}";
}

sub validate_pin {
   my $self = shift;
   my $group = shift;
   my $pin = shift;
   if( !$pin_caps{$group} ) {
     &{ $self->{msg}}(printf("Skipping pin %s%s: Invalid pingroup passed [%s] valid: A-G\n", $group, $pin, $group));
     return 0;
   } elsif( !$pin_caps{$group}[$pin] ) {
     &{ $self->{msg}}(printf("Skipping pin %s%s: Invalid pin [%s] valid: 0-15\n", $group, $pin, $pin));
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
    &{ $self->{msg} }(sprintf("Backwards compatable setup detected, mapping %s to %s\n", $cfg, get_cap_name($compat_map)));
    $cfg = $compat_map;
  }
  

  if( !validate_pin($self, $group,$pin) ) {
  } elsif( !has_cap($group, $pin, $cfg) ) {
     &{ $self->{msg} }(sprintf("Skipping pin %s%s: Invalid state was requested [%s] valid: {%s}\n", 
            $group, $pin, get_cap_name($cfg), get_caps($group, $pin)));
  } elsif( cap_qty($cfg) > 1 ) {
     &{ $self->{msg} }(sprintf("Skipping pin %s%s: Cannot set multiple states simultaneously [%s] valid: {%s}",
            $group, $pin, get_cap_name($cfg), get_caps($group, $pin)));
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
          &{ $self->{msg} }(sprintf("Too many Software PWM Channels Configured: [%s] max: [64]\n", $count));
	  return 1;
	}
     	$cmd = sprintf("PC,4,%s\nPC,2,%s,%s,%s",$count,$free_channel,$group,$pin);
     } elsif( $cfg & $caps{HardPWMOut} ) {
       #Stupidly assuming a pin must be set to Digital Output to PWM
       $cmd = sprintf("PD,%s,%s,%s" , $group,$pin,0);
     } else {
       # Maybe this should explicitly print
       &{ $self->{msg} }(sprintf("This shouldn't happen(Using an old library with code written for new module?).".
                              "  Please report: [%s][%s][%s]\n",$group,$pin,$cfg));
       return 1;
     }
     if( !$self->{dbg} ) {
       if( $self->{pinconfigs}{$group}[$pin]{mode} == $caps{HardPWMOut} ) {
         # We must disable Hardware PWM before setting a new mode
         hw_pwm($self, $group, $pin, 0);
       }
       $self->{port}->write("$cmd\n");
       $self->{port}->write_drain;
       usleep(10*1000);
       $result = $self->{port}->read(255);
     } else {
       $result = "OK";
     }
     if( $result !~ /OK/ ) {
       &{ $self->{msg} }(sprintf("Pin configuration failed: [%s][$cmd]\n", $result));
     } else {
       &{ $self->{msg} }(sprintf("Pin %s%s configured as %s\n", $group, $pin, get_cap_name($cfg)));
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

  if( $val_bit < 0 ) {
     &{ $self->{msg} }(sprintf("Skipping pin %s%s: Invalid pin state was passed [%s] valid: {high,low}\n", $group, $pin, $value));
  } elsif( !validate_pin($self,$group,$pin) ){
  } elsif( $self->{pinconfigs}{$group}[$pin]{mode} != $caps{DigitalOut} ) {
     &{ $self->{msg} }(sprintf("Skipping pin %s%s: Pin is not set to output[%s]\n",
            $group, $pin, get_cap_name($self->{pinconfigs}{$group}[$pin]{mode})));
  } else {
    my $cmd = sprintf("PO,%s,%s,%s", $group,$pin,$val_bit);
    if(!$self->{dbg}){
      $self->{port}->write("$cmd\n");
      $self->{port}->write_drain;
      usleep(7.5*1000);
      $result = $self->{port}->read(255);
    } else {
      $result = sprintf("%s\nOK\n", $cmd);
    }
    if( $result !~ /OK/ ) {
       printf("Pin state failed: [%s]\n", $result);
    } else {
       $self->{pinconfigs}{$group}[$pin]{state} = $value;
       return 0;
    }
  }
  return 1;
}

sub get_pin {
  my $self = shift;
  my $group = shift;
  my $pin = shift;

  my $result = "";

  if( !validate_pin($self,$group,$pin) ){
  } elsif( $self->{pinconfigs}{$group}[$pin]{mode} != $caps{DigitalIn} ) {
     &{ $self->{msg} }(sprintf("Skipping read of %s%s: Pin is not set to input[%s]\n",
            $group, $pin, get_cap_name($self->{pinconfigs}{$group}[$pin]{mode})));
  } else {
    my $cmd = sprintf("PI,%s,%s", $group, $pin);
    if(!$self->{dbg}){
      $self->{port}->write("$cmd\n");
      $self->{port}->write_drain;
      usleep(7.5*1000);
      $result = $self->{port}->read(255);
    } else {
      my $tempbit = int(rand() + .5);
      $result = sprintf("%s\nPI,%s\nOK\n", $cmd, $tempbit);;
    }
    if( $result !~ /OK/ ) {
      printf("Reading Pin failed: [%s]\n", $result);
    } else {
      $result =~ /$cmd\nPI,(?<bit>[01])[\n\r]*OK/m;
      return $+{bit};
    }
  }
  return -1;
}

sub get_analog {
  my $self = shift;
  my $group = shift;
  my $pin = shift;
  my $samples = shift;
  my $interval = shift; # us
  my %output;

  if( !validate_pin($self,$group,$pin) ){
  } elsif( $self->{pinconfigs}{$group}[$pin]{mode} != $caps{AnalogIn} ) {
    &{ $self->{msg} }(sprintf("Skipping read of %s%s: Pin is not set to Analog Input[%s]\n",
           $group, $pin, get_cap_name($self->{pinconfigs}{$group}[$pin]{mode})));
  } else {
    my $pinmask = analog_mask($group,$pin);
    my $cmd = sprintf("IA,%s,%s,%s", $pinmask, $interval, $samples);
    my $result;
    if(!$self->{dbg}){
      $self->{port}->write("$cmd\n");
      $self->{port}->write_drain;
      usleep(7.5*1000 + $samples * $interval);
      #  Command sent, new line, maximum analog string length * sample rate (and Commas), new line, OK, new line, and 1 safety
      my $readlen = length($cmd) + 2 + 5 * $samples + 2 + 2 + 2 + 1;
      $result = $self->{port}->read($readlen); 
    } else {
      my @tmp;
      for(my $i=0; $i < $samples; $i++) {
        push(@tmp, int(rand(1024)));
      }
      $result = sprintf("%s\nIA,%s\nOK\n", $cmd, join(",", @tmp));
    }
    if($result !~ /OK/) {
      printf("Reading Pin failed: [%s]\n", $result);
    } else {
      # must match \n\r instead of \n.  get analog is returning \r\r instead of a standard newline
      $result =~ m/$cmd\nIA,(?<pin>[\d\,]+)[\n\r]+OK/m;
      my @a = split(/,/,$+{pin});
      $output{$group}[$pin] = [@a];
    }
  }  
  return %output;
}

sub hw_pwm {
  my $self = shift;
  my $group = shift;
  my $pin = shift;
  my $duty_cycle = int(shift);
  if( !validate_pin($self,$group,$pin) ) {
  } elsif($self->{pinconfigs}{$group}[$pin]{mode} != $caps{HardPWMOut} ){
    &{ $self->{msg} }(sprintf("Skipping setting PWM on %s%s: Pin is not set to Hardware PWM[%s]\n",
           $group, $pin, get_cap_name($self->{pinconfigs}{$group}[$pin]{mode})));
  } else {
    my $chan = $hwpwm_pins{$group}[$pin];
    my $cmd = sprintf("PM,%s,%s", $chan, $duty_cycle);
    my $result;
    if(! $self->{dbg} ){
      $self->{port}->write("$cmd\n");
      $self->{port}->write_drain;
      usleep(7.5*1000);
      $result = $self->{port}->read(length($cmd) + 2 + 2 + 2 + 1);
    } else {
      $result = sprintf("%s\nOK\n", $cmd);
    }
    if($result !~ /OK/) {
      &{ $self->{msg} }(sprintf("Setting HW Pwm on Pin failed: [%s]\n", $result));
    } else {
      return 0;
    }
  }
  return 1;
}

1;
