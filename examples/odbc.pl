
#
# This is a simple server that listens for incoming connections from the MySQL ODBC driver.
# It detects several common queries that the ODBC and Microsoft Access issue in order to 
# probe the connection and the available tables and databases.
#
# If the Import Table function of Microsoft Access is used, $resulset is returned and imported
# into Microsoft Access. The behavoir of this sample script is undefined for all other purposes,
# and will not work with the "Link Tables" function.
#
# This script should also work with Import External Data in Microsoft Excel, if you are importing
# the entire data using the default path through the Wizard, that is, without using Microsoft Query
#
# Also please note that this script is entirely machinistic -- it does not analyse the queries that
# it answers. If a query is received that is not one of the expected ones, the script will return
# and error message. This may cause your Microsoft Access to crash or otherwise misbehave and you
# may need to close it and open it again.
#
# It was tested using Microsoft Access XP on Windows 2000 with MyODBC 3.51. Your mileage may vary,
# however if you have made the script work in a different setup,
# please let the author know at philip at stoev dot org
#
# To keep the example simple, this implementation accepts only one connection at a time. Since
# Microsoft Access may try to establish a new connection for each table being imported, this script
# will close the current connection once the data from $resultset has been sent. This allows you to
# import multiple tables without having to restart Access
#

my $port = '23306';
my $database = 'mydb';
my $table = 'mytable';
my $field_count = 5;
my $field = 'myfield';

my $resultset = [
	['1data1','1data2','1data3','1data4','1data5'],
	['2data1','2data2','2data3','2data4','2data5']
];

use strict;
use Socket;
use DBIx::MyServer;

socket(SERVER_SOCK, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
setsockopt(SERVER_SOCK, SOL_SOCKET, SO_REUSEADDR, pack("l", 1));
bind(SERVER_SOCK, sockaddr_in($port, INADDR_ANY)) || die "bind: $!";
listen(SERVER_SOCK,1);

print localtime()." [$$] Please open a ODBC connection to port $port to connect.\n";
print localtime()." [$$] Note that this port is by default open to anyone.\n";

while (1) {
	my $remote_paddr = accept(my $remote_socket, SERVER_SOCK);
	my $myserver = DBIx::MyServer->new( socket => $remote_socket );

	$myserver->sendServerHello();	# Those three together are identical to
	$myserver->readClientHello();	#	$myserver->handshake()
	$myserver->sendOK();		# which uses the default authorize() handler

	while (1) {
		my ($command, $data) = $myserver->readCommand();
		print localtime()." [$$] Command: $command; Data: $data\n";
		if (
			(not defined $command) ||
			($command == DBIx::MyServer::COM_QUIT)
		) {
			last;
		} elsif ($command == DBIx::MyServer::COM_FIELD_LIST) {
			$myserver->sendDefinitions([
				map {
					$myserver->newDefinition(
						catalog => $database,
						database => $database,
						table => $table,
						name => 'myfield'.$_,
						org_name => 'myfield'.$_
					)
				} (1..$field_count)
			],1);
			$myserver->sendEOF();			
		} elsif (
				($command == DBIx::MyServer::COM_PING) ||
				($command == DBIx::MyServer::COM_INIT_DB)
		) {
			$myserver->sendOK();
		} elsif ($command == DBIx::MyServer::COM_QUERY) {
			my ($header, $result, $finish);
			if (
				($data eq 'SET SQL_AUTO_IS_NULL=0;') ||
				($data eq 'set autocommit=1')
			) {
				$myserver->sendOK();
			} elsif ($data eq 'SELECT Config, nValue FROM MSysConf') {
				$myserver->sendError("MSysConf does not exist", 1146, '42S02');
			} elsif (
					($data eq 'select database()') ||
					($data =~ m{^show databases}io)
			) {
				$header = ['Database'];
				$result = [[$database]];
			} elsif ($data eq 'show tables') {
				$header = ['Tables_in_'.$database];
				$result = [[$table]];
			} elsif ($data eq "SHOW TABLES FROM `mysql` like '%'") {
				$header = ['Tables_in_mysql (%)'];		# Return no rows
			} elsif ($data eq "SHOW KEYS FROM `$table`") {
				$header = ['Keys'];				# Return no rows
			} elsif ($data =~ m{SELECT .* FROM .*`$table`}sio) {
				$header = [map{ "field".$_ } (1..$field_count)];
				$result = $resultset;
				$finish = 1;
			} else {
				$myserver->sendErrorUnsupported($command);
			}

			if (defined $header) {
				$myserver->sendDefinitions([
					map {
						$myserver->newDefinition( name => $_ )
					} @$header]);
				$myserver->sendRows($result);
			}
			last if $finish;
		} else {
			$myserver->sendErrorUnsupported($command);
		}
	}
}
