package RT::ClientX::GrabBugs::Bug;

use 5.010;
use namespace::autoclean;
use utf8;

BEGIN {
	$RT::ClientX::GrabBugs::Bug::AUTHORITY = 'cpan:TOBYINK';
	$RT::ClientX::GrabBugs::Bug::VERSION   = '0.001';
}

use Moose;
use RDF::Trine qw/statement iri literal blank/;

use RDF::Trine::Namespace qw/rdf rdfs owl xsd/;
my $dbug   = RDF::Trine::Namespace->new('http://ontologi.es/doap-bugs#');
my $dc     = RDF::Trine::Namespace->new('http://purl.org/dc/terms/');
my $doap   = RDF::Trine::Namespace->new('http://usefulinc.com/ns/doap#');
my $foaf   = RDF::Trine::Namespace->new('http://xmlns.com/foaf/0.1/');
my $status = RDF::Trine::Namespace->new('http://purl.org/NET/cpan-uri/rt/status/');
my $prio   = RDF::Trine::Namespace->new('http://purl.org/NET/cpan-uri/rt/priority/');

has person_cache => (
	is       => 'ro',
	isa      => 'HashRef',
	default  => sub { +{} },
	);

has [qw/id Queue Subject Status TimeEstimated TimeWorked TimeLeft Priority
	FinalPriority Owner Requestors Cc AdminCc Due Told Created Resolved
	LastUpdated LastUpdatedBy CF_Severity CF_Broken_in CF_Fixed_in/]
	=> (
	is       => 'ro',
	isa      => 'Str',
	required => 0,
	);

sub add_to_model
{
	my ($self, $model) = @_;
	
	my $proj = iri(sprintf('http://purl.org/NET/cpan-uri/dist/%s/project', $self->Queue));
	my $iri  = iri(sprintf('http://purl.org/NET/cpan-uri/rt/ticket/%d', $self->id));
	
	$model->add_statement(statement($proj, $dbug->issue, $iri));
	$model->add_statement(statement($iri, $rdf->type, $dbug->Issue));
	$model->add_statement(statement($iri, $dbug->page, iri(sprintf q{https://rt.cpan.org/Ticket/Display.html?id=%d}, $self->id)));
	$model->add_statement(statement($iri, $dbug->id, literal($self->id, undef, $xsd->string)));
	$model->add_statement(statement($iri, $rdfs->label, literal($self->Subject)));
	$model->add_statement(statement($iri, $dbug->reporter, $self->_person($model, $self->Requestors)));
	$model->add_statement(statement($iri, $dbug->assignee, $self->_person($model, $self->Owner)));
	$model->add_statement(statement($iri, $dc->created, $self->_date($model, $self->Created)));
	$model->add_statement(statement($iri, $dc->modified, $self->_date($model, $self->LastUpdated)));
	$model->add_statement(statement($iri, $dbug->status, $status->uri(lc $self->Status)));
}

sub _person
{
	my ($self, $model, $string) = @_;
	
	unless ($self->person_cache->{$string})
	{
		$self->person_cache->{$string} = my $node = blank();
		$model->add_statement(statement($node, $rdf->type, $foaf->Agent));
		if ($string =~ /\@/)
		{
			$model->add_statement(statement($node, $foaf->mbox, iri('mailto:'.$string)));
		}
		else
		{
			$model->add_statement(statement($node, $foaf->nick, literal($string)));
		}
	}
	
	$self->person_cache->{$string};
}

sub _date
{
	my ($self, $model, $string) = @_;
	
	if ($string =~ /^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})$/)
	{
		return literal("${1}T${2}", undef, $xsd->dateTime);
	}
	
	literal($string);
}

__PACKAGE__
__END__

=head1 NAME

RT::ClientX::GrabBugs::Bug - shallow representation of a bug

=head1 DESCRIPTION

=head2 Constructor

Fairly standard Moosey C<new> constructor, accepting a hash of named
parameters.

=head2 Attributes

Read-only strings:

=over

=item * id

=item * Queue

=item * Subject

=item * Status

=item * TimeEstimated

=item * TimeWorked

=item * TimeLeft

=item * Priority

=item * FinalPriority

=item * Owner

=item * Requestors

=item * Cc

=item * AdminCc

=item * Due

=item * Told

=item * Created

=item * Resolved

=item * LastUpdated

=item * LastUpdatedBy

=item * CF_Severity

=item * CF_Broken_in

=item * CF_Fixed_in

=back

There is also an attribute C<person_cache> which is a hashref for caching
descriptions of people into. This is handy if you expect some people (e.g.
bug owners, requestors, etc) to appear in multiple bugs. The bugs can all
share a reference to the same hash for caching people.

=head2 Methods

=over

=item * C<< add_to_model($model) >>

Adds a description of the bug to an RDF::Trine::Model.

=back

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=RT-ClientX-GrabBugs>.

=head1 SEE ALSO

L<RT::ClientX::GrabBugs>.

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

