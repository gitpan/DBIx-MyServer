# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl DBIx-MyServer.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 2;
BEGIN { use_ok('DBIx::MyServer') };

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

unless ($pid = fork) {
    print "Spawning a MySQL test server on port 23306, pid=$$...\n";
    exec("perl examples/odbc.pl");
}

sleep 1;

use DBI;

my $dbh = DBI->connect('dbi:mysql:host=127.0.0.1:port=23306');
my $result = $dbh->selectrow_array("SELECT * FROM `mytable`");
ok($result eq '1data1', 'myserver');
kill(15,$pid);

