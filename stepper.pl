#!/bin/perl

use strict;
use Device::SerialPort;
use Time::HiRes qw(usleep nanosleep);

my $serialport = "/dev/ttyACM0";

my %motors = (
   pan => {
      # Wiring specific
      pins	=> [ "step","direction","ms1","ms2","slp" ],
      step 	=> [ "C", "1", "out", "low" ],
      direction => [ "E", "7", "out", "low" ],
      ms1	=> [ "C", "3", "out", "low" ],
      ms2	=> [ "C", "2", "out", "low" ],
      slp	=> [ "E", "6", "out", "low" ],
      ccw	=> "low",
      cw	=> "high",
      # Controller specific
      holdtime  => 7.5 * 1000,
      sleepval  => "low",
      # Motor specific
      stepsize	=> 1.8,
      canustep  => 1,
      usteps	=> {
        whole 	=> ["low","low",1],
	half  	=> ["high","low",0.5],
	quarter	=> ["low","high",0.25],
	eighth	=> ["high","high",0.125],
      },
   },
   tilt => {
      # Wiring specific
      pins	=> [ "step","direction","ms1","ms2","slp" ],
      step 	=> [ "D", "5", "out", "low" ],
      direction => [ "D", "4", "out", "low" ],
      ms1	=> [ "D", "7", "out", "low" ],
      ms2	=> [ "D", "6", "out", "low" ],
      slp	=> [ "D", "13", "out", "low" ],
      ccw	=> "low",
      cw	=> "high",
      # Controller specific
      holdtime  => 7.5 * 1000,
      sleepval	=> "low",
      # Motor specific
      stepsize	=> 1.8,
      canustep  => 1,
      usteps	=> {
        whole 	=> ["low","low",1],
	half  	=> ["high","low",0.5],
	quarter	=> ["low","high",0.25],
	eighth	=> ["high","high",0.125],
      },
   },
);

# Abandon all hope, ye who enter here
#

my $dbg = 0;

my $port;
my %pinconfigs;

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
     if( !$dbg ) {
       $port->write("$cmd\n");
       $port->write_drain;
       usleep(10*1000);
       $result = $port->read(255);
     } else {
       $result = "OK";
     }
     if( $result !~ /OK/ ) {
	printf("Pin configuration failed: [%s][$cmd]\n", $result);
     } else {
       $pinconfigs{"$group$pin"}{direction} = $dir;
       $pinconfigs{"$group$pin"}{state} = "Unknown";
     }
  }
}

sub set_pin {
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
  } elsif( $pinconfigs{"$group$pin"}{direction} ne "out" ) {
     printf("Skipping pin %s%s: Pin is set to input or no direction explicitly set\n", $group, $pin);
  } else {
    if(!$dbg){
      $port->write("$cmd\n");
      $port->write_drain;
      usleep(7.5*1000);
      $result = $port->read(255);
    } else {
      $result = "OK";
    }
    if( $result !~ /OK/ ) {
       printf("Pin state failed: [%s]\n", $result);
    } else {
       $pinconfigs{"$group$pin"}{state} = $value;
    }
  }
}

sub print_pin {
  my @cfg = @{$_[0]};
  return "${cfg[0]}${cfg[1]}";
}

sub list_motors {
  my $name;
  foreach $name (keys(%motors)) {
    printf("Motor: %s [ Step: %s, Direction: %s ]\n",
           $name, 
	   print_pin(\@{$motors{$name}{step}}),
	   print_pin(\@{$motors{$name}{direction}})
    );
  }
}

sub configure_motor_pins {
  my $motor;
  my $function;
  foreach $motor (keys(%motors)) {
    foreach $function (@{$motors{$motor}{pins}}) {
      
      my $group = $motors{$motor}{$function}[0];
      my $pin   = $motors{$motor}{$function}[1];
      my $dir   = $motors{$motor}{$function}[2];
      my $value = $motors{$motor}{$function}[3];

      printf("Configuring: %s -> %s\n", $motor, $function);
      configure_pin($group, $pin, $dir);
      if($dir eq "out") {
        set_pin($group, $pin, $value);
      }
    }
  }
}

sub step_motor {
  my $motor = shift;
  my $direction = shift;
  my $angle = shift;
  my $ustepping = shift;

  my @stepcfg = @{$motors{$motor}{step}};
  my @dircfg  = @{$motors{$motor}{direction}};
  my @ms1cfg  = @{$motors{$motor}{ms1}};
  my @ms2cfg  = @{$motors{$motor}{ms2}};

  my $dir_bit = $motors{$motor}{$direction};
  my $steps = $angle / $motors{$motor}{stepsize};
  
  set_pin($dircfg[0], $dircfg[1], $dir_bit);

  if($motors{$motor}{canustep}){
    if($ustepping) {
      my @ustepcfg = @{$motors{$motor}{usteps}{$ustepping}};
      set_pin($ms1cfg[0], $ms1cfg[1], $ustepcfg[0]);
      set_pin($ms2cfg[0], $ms2cfg[1], $ustepcfg[1]);
      $steps /= $ustepcfg[2];
    }
  }

  for(; $steps > 0; $steps--) {
    set_pin($stepcfg[0], $stepcfg[1], "high");
    usleep($motors{$motor}{holdtime});
    set_pin($stepcfg[0], $stepcfg[1], "low");
  }
}

sub sleep_motor {
  my $motor = shift;
  my @sleepcfg = @{$motors{$motor}{slp}};
  my $sleepval = $motors{$motor}{sleepval};
  
  set_pin($sleepcfg[0], $sleepcfg[1], $sleepval);
}

sub wake_motor {
  my $motor = shift;
  my @sleepcfg = @{$motors{$motor}{slp}};
  my $sleepval = $motors{$motor}{sleepval};

  set_pin($sleepcfg[0], $sleepcfg[1], $sleepval eq "high" ? "low" : "high");
}

if(!$dbg) {
  $port = Device::SerialPort->new("/dev/ttyACM0");
  $port->databits(8);
  $port->baudrate(9600);
  $port->parity("none");
  $port->stopbits(1);
}

#testing
#exit(0)
#
#set_pin("A","0","low");
#configure_pin("Z","0","in");
#configure_pin("A","0","bi");
#configure_pin("A","0","in");
#set_pin("A","0","middle");
#configure_pin("A","0","out");
#set_pin("A","0","high");

list_motors();
configure_motor_pins();

wake_motor("tilt");
sleep 1;
printf("Rotating 90 degrees whole step\n");
step_motor("tilt", "cw", 90, "whole");
sleep 1;
printf("Rotating 90 degrees half step\n");
step_motor("tilt", "cw", 90, "half");
sleep 1;
printf("Rotating 90 degrees quarter step\n");
step_motor("tilt", "cw", 90, "quarter");
sleep 1;
printf("Rotating 90 degrees eighth step\n");
step_motor("tilt", "cw", 90, "eighth");
sleep 1;
sleep_motor("tilt");
