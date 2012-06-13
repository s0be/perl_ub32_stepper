#!/bin/perl

use strict;
use Time::HiRes qw(usleep nanosleep);
use UBW32 qw(:DEFAULT %caps);
my $serialport = "/dev/ttyACM0";

my $ubw=UBW32->new($serialport);

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


sub list_motors {
  my $name;
  foreach $name (keys(%motors)) {
    printf("Motor: %s [ Step: %s, Direction: %s ]\n",
           $name, 
	   $ubw->print_pin(\@{$motors{$name}{step}}),
	   $ubw->print_pin(\@{$motors{$name}{direction}})
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
      $ubw->configure_pin($group, $pin, $dir);
      if($dir eq "out") {
        $ubw->set_pin($group, $pin, $value);
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
  
  $ubw->set_pin($dircfg[0], $dircfg[1], $dir_bit);

  if($motors{$motor}{canustep}){
    if($ustepping) {
      my @ustepcfg = @{$motors{$motor}{usteps}{$ustepping}};
      $ubw->set_pin($ms1cfg[0], $ms1cfg[1], $ustepcfg[0]);
      $ubw->set_pin($ms2cfg[0], $ms2cfg[1], $ustepcfg[1]);
      $steps /= $ustepcfg[2];
    }
  }

  for(; $steps > 0; $steps--) {
    $ubw->set_pin($stepcfg[0], $stepcfg[1], "high");
    usleep($motors{$motor}{holdtime});
    $ubw->set_pin($stepcfg[0], $stepcfg[1], "low");
  }
}

sub sleep_motor {
  my $motor = shift;
  my @sleepcfg = @{$motors{$motor}{slp}};
  my $sleepval = $motors{$motor}{sleepval};
  
  $ubw->set_pin($sleepcfg[0], $sleepcfg[1], $sleepval);
}

sub wake_motor {
  my $motor = shift;
  my @sleepcfg = @{$motors{$motor}{slp}};
  my $sleepval = $motors{$motor}{sleepval};

  $ubw->set_pin($sleepcfg[0], $sleepcfg[1], $sleepval eq "high" ? "low" : "high");
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
#leep 1;
printf("Rotating 90 degrees whole step\n");
step_motor("tilt", "cw", 90, "whole");
#leep 1;
#printf("Rotating 90 degrees half step\n");
#step_motor("tilt", "cw", 90, "half");
#sleep 1;
#printf("Rotating 90 degrees quarter step\n");
#step_motor("tilt", "cw", 90, "quarter");
#sleep 1;
#printf("Rotating 90 degrees eighth step\n");
#step_motor("tilt", "cw", 90, "eighth");
#sleep 1;
sleep_motor("tilt");

wake_motor("tilt");
#leep 1;
printf("Rotating 90 degrees whole step\n");
step_motor("tilt", "ccw", 90, "whole");
#leep 1;
#printf("Rotating 90 degrees half step\n");
#step_motor("tilt", "ccw", 90, "half");
#sleep 1;
#printf("Rotating 90 degrees quarter step\n");
#step_motor("tilt", "ccw", 90, "quarter");
#sleep 1;
#printf("Rotating 90 degrees eighth step\n");
#step_motor("tilt", "ccw", 90, "eighth");
#sleep 1;
sleep_motor("tilt");

wake_motor("pan");
#leep 1;
printf("Rotating 90 degrees whole step\n");
step_motor("pan", "cw", 90, "whole");
#leep 1;
#printf("Rotating 90 degrees half step\n");
#step_motor("pan", "cw", 90, "half");
#sleep 1;
#printf("Rotating 90 degrees quarter step\n");
#step_motor("pan", "cw", 90, "quarter");
#sleep 1;
#printf("Rotating 90 degrees eighth step\n");
#step_motor("pan", "cw", 90, "eighth");
#sleep 1;
sleep_motor("pan");

wake_motor("pan");
#leep 1;
printf("Rotating 90 degrees whole step\n");
step_motor("pan", "ccw", 90, "whole");
#leep 1;
#printf("Rotating 90 degrees half step\n");
#step_motor("pan", "ccw", 90, "half");
#sleep 1;
#printf("Rotating 90 degrees quarter step\n");
#step_motor("pan", "ccw", 90, "quarter");
#sleep 1;
#printf("Rotating 90 degrees eighth step\n");
#step_motor("pan", "ccw", 90, "eighth");
#sleep 1;
sleep_motor("pan");

# For this test, we have Pin F8 wired through a resister to B5
# With an LED through a resister to ground in parallel to B5 so that:
#
# Setting F8 high will put 2.8v onto B5 (allowing B5 to be Digital High
# but not 3.3v for Analog in).  Also, B5 can be low and F8 can go high and
# light the LED.

$ubw->configure_pin("F","8",$caps{DigitalOut});
$ubw->configure_pin("B","5",$caps{DigitalIn});
$ubw->set_pin("F","8","low");
