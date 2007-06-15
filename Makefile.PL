use 5.008008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'DBIx::MyServer',
    VERSION_FROM      => 'lib/DBIx/MyServer.pm', # finds $VERSION
    PREREQ_PM         => {'Digest::SHA1' => '2.11'},
	($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/DBIx/MyServer.pm', # retrieve abstract from module
       AUTHOR         => 'Philip Stoev <philip@stoev.org>') : ()),
);
