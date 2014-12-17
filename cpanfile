requires 'Mojolicious' => '5.37';
requires 'Mojolicious::Plugin::Recaptcha';
requires 'Mojolicious::Plugin::Mail';
requires 'Mojolicious::Plugin::Gravatar';
requires 'Mojolicious::Plugin::CSRFDefender';

requires 'Moose';
requires 'DBI';

requires 'Class::Load';
requires 'Crypt::Blowfish';
requires 'Crypt::Simple';
requires 'Data::Serializer';
requires 'Data::UUID';
requires 'DBD::mysql';
requires 'Digest::SHA2';
requires 'Email::Valid';
requires 'File::Slurp';
requires 'HTML::Entities';
requires 'JSON';
requires 'List::MoreUtils';
requires 'Params::Util';
requires 'Text::CSV';
requires 'Try::Tiny';
requires 'Validate::Tiny';

requires 'Net::Amazon::S3'            => 0, git => 'git://github.com/SDSWanderer/net-amazon-s3.git'; #Version on Cpan hasn't fix https://github.com/pfig/net-amazon-s3/pull/45
requires 'Hash::Storage'              => 0, git => 'git://github.com/koorchik/Hash-Storage.git';
requires 'Query::Abstract'            => 0, git => 'git://github.com/koorchik/Query-Abstract.git';
requires 'Hash::Storage::Driver::DBI' => 0, git => 'git://github.com/koorchik/Hash-Storage-Driver-DBI.git';

requires 'experimental';