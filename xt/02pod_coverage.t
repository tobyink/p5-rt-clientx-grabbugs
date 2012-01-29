use Test::More;
use Test::Pod::Coverage;

my @modules = qw(RT::ClientX::GrabBugs RT::ClientX::GrabBugs::Bug);
pod_coverage_ok($_, "$_ is covered")
	foreach @modules;
done_testing(scalar @modules);

