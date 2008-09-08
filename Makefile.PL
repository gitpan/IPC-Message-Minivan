use inc::Module::Install;
BEGIN { require 5.008 } # please CPAN::Reporter

# Define metadata
name            'IPC-Message-Minivan';
all_from        'lib/IPC/Message/Minivan.pm';
license         'bsd';

# Specific dependencies
requires        'IPC::Messaging'   => '0.01_11';
requires        'JSON::XS' => 2.1;
requires        'Time::HiRes'      => 0;

recommends      'IO::KQueue'       => 0;

build_requires  'Test::More'       => 0;

no_index        'directory'        => 'devel';
install_script  'minivan';

if ( $^O eq 'MSWin32' ) {
	die "This distribution would not work on Windows platform.\n";
}

#auto_install;
WriteAll;
