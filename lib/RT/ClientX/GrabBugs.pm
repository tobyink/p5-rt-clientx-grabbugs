package RT::ClientX::GrabBugs;

use 5.010;
use autodie;
use namespace::autoclean;
use utf8;

BEGIN {
	$RT::ClientX::GrabBugs::AUTHORITY = 'cpan:TOBYINK';
	$RT::ClientX::GrabBugs::VERSION   = '0.001';
}

use Getopt::ArgvFile justload => 1;
use Getopt::Long qw/GetOptionsFromArray/;
use HTTP::Cookies;
use Module::Install::Admin::RDF;
use Moose;
use Web::Magic -quotelike => qw/web/;

has [qw/user pass/] => (
	is       => 'ro',
	isa      => 'Str',
	required => 1,
	);

has queue => (
	is       => 'ro',
	isa      => 'Str',
	lazy     => 1,
	builder  => '_build_queue',
	);

has queue_table => (
	is       => 'ro',
	isa      => 'ArrayRef',
	lazy     => 1,
	builder  => '_build_queue_table',
	);

has queue_model => (
	is       => 'ro',
	isa      => 'RDF::Trine::Model',
	lazy     => 1,
	builder  => '_build_queue_model',
	);

has dest => (
	is       => 'ro',
	isa      => 'Str',
	default  => './meta/rt-bugs.ttl',
	);

has bug_class => (
	is       => 'ro',
	isa      => 'Str',
	default  => join('::', __PACKAGE__, 'Bug'),
	);

# Hacks to trick Module::Install::Admin::RDF
{
	sub _top            { $_[0] }
	sub rdf_metadata    { Module::Install::Admin::RDF::rdf_metadata(@_) }
	sub rdf_project_uri { Module::Install::Admin::RDF::rdf_project_uri(@_) }
}

sub main
{
	my ($class, @argv) = @_;
	
	Getopt::ArgvFile::argvFile(
		array           => \@argv,
		startupFilename => '.rt-grabbugs',
		current         => 1,
		home            => 1,
		);
	
	GetOptionsFromArray(\@argv, \(my %opts),
		'queue=s',
		'dest=s',
		'user=s',
		'pass=s',
		);
	
	$class->new(%opts)->process;
}

sub _build_queue
{
	my ($self)  = @_;
	my $doapuri = $self->rdf_project_uri;
	
	if ($doapuri =~ qr{ <http://purl.org/NET/cpan-uri/dist/(.+)/project> }x)
	{
		return $1;
	}
	
	confess "Unable to determine RT queue. Please specify manually.";
}

sub _build_queue_table
{
	my ($self)  = @_;
	
	# Need to use cookies for logging in.
	local $Web::Magic::user_agent = LWP::UserAgent->new(
		cookie_jar => HTTP::Cookies->new,
		agent      => sprintf('%s/%s ', __PACKAGE__, __PACKAGE__->VERSION),
		);
	
	web <https://rt.cpan.org/NoAuth/Login.html>
		-> POST({ user => $self->user, pass => $self->pass });
	
	# Stupidly long URL. Some can probably be cut down.
	my $template = join '', qw{
		https://rt.cpan.org/Search/Results.tsv?Format=%%0A%%20%%20%%20'
		%%3CB%%3E%%3CA%%20HREF%%3D%%22__WebPath__%%2FTicket%%2FDisplay.
		html%%3Fid%%3D__id__%%22%%3E__id__%%3C%%2Fa%%3E%%3C%%2FB%%3E
		%%2FTITLE%%3A%%23'%%2C%%0A%%20%%20%%20'%%3CB%%3E%%3CA%%20HREF
		%%3D%%22__WebPath__%%2FTicket%%2FDisplay.html%%3Fid%%3D__id__
		%%22%%3E__Subject__%%3C%%2Fa%%3E%%3C%%2FB%%3E%%2FTITLE%%3ASubject
		'%%2C%%0A%%20%%20%%20Status%%2C%%0A%%20%%20%%20QueueName%%2C%%20
		%%0A%%20%%20%%20OwnerName%%2C%%20%%0A%%20%%20%%20Priority%%2C%%20
		%%0A%%20%%20%%20'__NEWLINE__'%%2C%%0A%%20%%20%%20''%%2C%%20%%0A
		%%20%%20%%20'%%3Csmall%%3E__Requestors__%%3C%%2Fsmall%%3E'%%2C
		%%0A%%20%%20%%20'%%3Csmall%%3E__CreatedRelative__%%3C%%2Fsmall
		%%3E'%%2C%%0A%%20%%20%%20'%%3Csmall%%3E__ToldRelative__%%3C%%2F
		small%%3E'%%2C%%0A%%20%%20%%20'%%3Csmall%%3E__LastUpdatedRelative__
		%%3C%%2Fsmall%%3E'%%2C%%0A%%20%%20%%20'%%3Csmall%%3E__TimeLeft__
		%%3C%%2Fsmall%%3E'&Order=ASC&OrderBy=id&Page=1&Query=Queue%%20%%3D
		%%20'%s')&Rows=50
		};
	my $uri = sprintf($template, $self->queue);
	my $tsv = web <$uri> -> assert_success;
	
	my @rows   = split /\r?\n/, $tsv;
	my @fields = map { $_ =~ s/\W/_/g; $_ }
		(split /\t/, shift @rows);
	
	my $cache = {};
	
	[ map {
		my %hash;
		@hash{ @fields } = split /\t/, $_;
		$self->bug_class->new(%hash, person_cache => $cache);
		} @rows ];
}

sub _build_queue_model
{
	my ($self) = @_;
	
	my $model = RDF::Trine::Model->new;
	my $queue = $self->queue_table;
	foreach my $bug (@$queue)
	{
		$bug->add_to_model($model);
	}
	
	$model;
}

sub process
{
	my ($self) = @_;
	
	open my $fh, '>:encoding(UTF-8)', $self->dest;
	
	RDF::Trine::Serializer::Turtle
		->new(namespaces => {
			dbug   => 'http://ontologi.es/doap-bugs#',
			dc     => 'http://purl.org/dc/terms/',
			doap   => 'http://usefulinc.com/ns/doap#',
			foaf   => 'http://xmlns.com/foaf/0.1/',
			rdfs   => 'http://www.w3.org/2000/01/rdf-schema#',
			rt     => 'http://purl.org/NET/cpan-uri/rt/ticket/',
			status => 'http://purl.org/NET/cpan-uri/rt/status/',
			prio   => 'http://purl.org/NET/cpan-uri/rt/priority/',
			xsd    => 'http://www.w3.org/2001/XMLSchema#',
			})
		->serialize_model_to_file($fh, $self->queue_model);
	
	$self;
}

__PACKAGE__
__END__

=head1 NAME

RT::ClientX::GrabBugs - download bugs from an RT queue and dump them as RDF

=head1 SYNOPSIS

 RT::ClientX::GrabBugs
   ->new({
     user      => $rt_username,
     pass      => $rt_password,
     queue     => $rt_queue,
     dest      => './output_file.ttl',
     })
   ->process;

=head1 DESCRIPTION

This module downloads bugs from an RT queue and dumps them as RDF.

=head2 Constructor

=over

=item C<< new(%attrs) >>

Fairly standard Moosey C<new> constructor, accepting a hash of named
parameters.

=item C<< main(@argv) >>

Alternative constructor. Processes C<< @argv >> like command-line arguments.
e.g.

 RT::ClientX::GrabBugs->main('--user=foo', '--pass=bar',
                             '--queue=My-Module');

This constructor uses L<Getopt::ArgvFile> to read additional options from
C<< ~/.rt-grabbugs >> and C<< ./.rt-grabbugs >>.

The constructor supports the options "--user", "--pass", "--queue" and
"--dest".

=back

=head2 Attributes

=over

=item * C<user>, C<pass>

Username and password for logging into RT.

=item * C<dest>

The file name where you want to save the data. This defaults to
"./meta/rt-bugs.ttl".

=item * C<queue>

Queue to grab bugs for. Assuming that you're grabbing from rt.cpan.org, this
corresponds to a CPAN distribution (e.g. "RT-ClientX-GrabBugs").

If not provided, this module will try to guess which queue you want. It does
this by looking for a subdirectory called "meta" in the current directory;
loading all the RDF in "meta"; and figuring out the doap:Project resource
which is best described. The heuristics work perfectly well for me, but
unless you package your distributions exactly like I do, they're unlikely
to work well for you. In which case, you should avoid this default behaviour.

=item * C<queue_table>

An arrayref of RT::ClientX::GrabBugs::Bug (see C<bug_class>) objects
representing all the bugs from a project.

By default, this module will build this by logging into RT and downloading it.
Here, you probably B<want> to rely on the default behaviour, because that's
the whole point of using the module.

=item * C<queue_model>

An RDF::Trine::Model generated by calling the C<add_to_model> method on each
bug in the C<queue_table> list. Again, here you probably want to rely on the
default.

=item * C<bug_class>

A class to bless bugs into, defaults to RT::ClientX::GrabBugs::Bug.

=back

=head2 Methods

=over

=item * C<< process >>

Saves the model from C<queue_model> to the destination C<dest> as Turtle.

Returns C<$self>.

=item * C<< rdf_metadata >>, C<< rdf_project_uri >>

Methods borrowed from L<Module::Install::Admin::RDF>.

=back

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=RT-ClientX-GrabBugs>.

=head1 SEE ALSO

L<RT::ClientX::GrabBugs::Bug>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2012 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

