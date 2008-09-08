package IPC::Message::Minivan;
use warnings;
use strict;
use 5.008;
use IPC::Messaging;
use JSON::XS;
use Time::HiRes;

use vars '$VERSION';
$VERSION = '0.01_05';

my $DEF_PORT = 6826;

sub new
{
	my ($class, %p) = @_;
	die "want host\n" unless $p{host};
	$p{port} ||= $DEF_PORT;
	eval { $p{sock} = IPC::Messaging->tcp_client($p{host}, $p{port}, by_line => 1); };
	$p{connected} = 0;
	$p{queue} = [];
	$p{chan} = {};
	$p{json} = JSON::XS->new->ascii->allow_nonref;
	my $me = bless \%p, $class;
	$me->_poll;
	$me;
}

sub subscribe
{
	my ($me, @chan) = @_;
	for my $chan (@chan) {
		$me->{chan}{$chan} = 1;
	}
	$me->_need_connect;
	return 0 unless $me->{connected};
	for my $chan (@chan) {
		syswrite $me->{sock}, "subscribe $chan\n";
	}
	return 1;
}

sub msg
{
	my ($me, $chan, $msg) = @_;
	$me->_need_connect;
	return 0 unless $me->{connected};
	my $json = $me->{json}->encode($msg);
	syswrite $me->{sock}, "put $chan $json\n";
	return 1;
}

sub get
{
	my ($me, @chan) = @_;
	$me->_poll;
	my $classify = 0;
	my $want_one = !wantarray;
	if (@chan == 1 && ref $chan[0]) {
		@chan = @{$chan[0]};
		$classify = 1;
	}
	my (@r, $r, $v, $found);
	unless (@chan) {
		my @m = @{$me->{queue}};
		$me->{queue} = [];
		for my $m (@m) {
			if (!$found) {
				$v = $me->{json}->decode($m->[1]);
				$v = [$m->[0], $v] if $classify;
				if ($want_one) {
					$r = $v;
					$found = 1;
				} else {
					push @r, $v;
				}
			} else {
				push @{$me->{queue}}, $m;
			}
		}
	} else {
		my %c = map { $_ => 1 } @chan;
		my @m = @{$me->{queue}};
		$me->{queue} = [];
		for my $m (@m) {
			if ($c{$m->[0]} && !$found) {
				$v = $me->{json}->decode($m->[1]);
				$v = [$m->[0], $v] if $classify;
				if ($want_one) {
					$r = $v;
					$found = 1;
				} else {
					push @r, $v;
				}
			} else {
				push @{$me->{queue}}, $m;
			}
		}
	}
	$want_one ? $r : @r;
}

sub _poll
{
	my ($me, $to) = @_;
	$to ||= 0;
	my $timeout = 0;
	if (!$me->{sock}) {
		eval { $me->{sock} = IPC::Messaging->tcp_client($me->{host}, $me->{port}, by_line => 1); };
		return unless $me->{sock};
	}
	while (1) {
		receive {
			got tcp_connected => $me->{sock} => then {
				$me->{connected} = 1;
				for my $chan (keys %{$me->{chan}}) {
					syswrite $me->{sock}, "subscribe $chan\n";
				}
			};
			got tcp_line => $me->{sock} => then {
				my $s = $_[1]->{line};
				$s =~ s/\r?\n?$//;
				if ($s =~ /^msg\s+(\S+)\s+(.*)$/) {
					push @{$me->{queue}}, [$1, $2];
				}
			};
			got tcp_error => $me->{sock} => then {
				$me->{connected} = 0;
				$me->{sock} = undef;
			};
			got tcp_disconnect => $me->{sock} => then {
				$me->{connected} = 0;
				$me->{sock} = undef;
			};
			after $to => then { $timeout = 1; };
		};
		$to = 0;
		return if $timeout;
		return unless $me->{sock};
	}
}

sub _need_connect
{
	my $me = shift;
	if ($me->{connected}) {
		$me->_poll;
	} else {
		$me->_poll(5);
	}
}

1;
__END__

=head1 NAME

IPC::Message::Minivan - a minimalistic message bus

=head1 VERSION

This document describes IPC::Message::Minivan version 0.01_05

=head1 SYNOPSIS

	my $van = IPC::Message::Minivan->new(host => 'localhost');
	# host is mandatory
	# port can be specified; 6826 is the default

	# Send a message to a channel "chan1".  The message
	# can be an arbitrary Perl data structure,
	# which should not be too big.
	$van->msg("chan1", $msg);

	# Get all pending messages from all subscribed channels,
	# no way to find out what the channel was for an
	# individual message
	my @m = $van->get;

	# Get all pending messages from specified channels,
	# no way to find out what the channel was for an
	# individual message
	my @m = $van->get("chan1", "chan2");

	# Get all pending messages from all subscribed channels.
	# Returns a list of arrayrefs, first element in each is the
	# channel name, second is the message.
	my @m = $van->get([]);

	# Get all pending messages from all subscribed channels.
	# Returns a list of arrayrefs, first element in each is the
	# channel name, second is the message.
	my @m = $van->get(["chan1", "chan2"]);

	# Get only the first pending message.  The variations above
	# apply, so:
	my $m = $van->get;
	my $m = $van->get("chan1", "chan2");
	my $m = $van->get([]);
	my $m = $van->get(["chan1", "chan2"]);

=head1 DESCRIPTION

IPC::Message::Minivan provides a minimalistic interface
to a minimalistic message bus.

There is no store-and-forward, there is no authentication,
there are no guarantees about delivery.  You've been warned.

Synopsis above more or less covers it all.

=head1 DEPENDENCIES

Perl 5.8.4 or above, IPC::Messaging, JSON::XS.

=head1 INCOMPATIBILITIES

This module, in all likelihood, will only work on Unix-like operating systems.

=head1 BUGS AND LIMITATIONS

Due to the current state of the IPC::Messaging module,
if a particular subscriber never calls get() and never
exits, the minivan daemon will eventually become clogged
and will stop delivering messages.  This should be fixed
in IPC::Messaging.

=head1 AUTHOR

Anton Berezin  C<< <tobez@tobez.org> >>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2008, Anton Berezin C<< <tobez@tobez.org> >>. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY AUTHOR AND CONTRIBUTORS ``AS IS'' AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
SUCH DAMAGE.
