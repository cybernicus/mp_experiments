#!/usr/bin/env perl
#
#   mp_w_shareall.pl <File>
#
#   Read & parse an MP file and simplify/summarize it
#
#   *NOTE* Parsing is crappy, as I just need a quick & dirty thing ATM.
#
#   20170126 - adapted from mp_summary.pl, parse into forest rather than AoA
#       
use strict;
use warnings;
use Data::Dump 'pp';
use MCMUtils;

use lib '.';
use mp_cheezparse;

my %cnt;

##### read the file #####

my $FName = shift or die "Missing MP file name";
open my $FH, '<', $FName or die "Can't open $FName: $!";
my @txt =   grep { ! /^$/ }
            map {s/\s+$//; $_}
            map { s/\/\/.*$//; $_ }     # rm comments
            <$FH>;

##### tokenize it #####
my $SRC = join(" ", @txt);
my @tokens = tokenize($SRC);
print scalar(@tokens), " tokens read\n";

##### split the tokens into statement groups (on semicolon) #####

my @stmts = statementize(@tokens);
print scalar(@stmts), " statements read\n";

my $RULES = parse(@stmts);

for my $r (values %$RULES) {
    if ($r->{ROOT}) { ++$cnt{ROOTS} } else { ++$cnt{RULES} }
    if ($r->{ATOM}) { ++$cnt{ATOMS} }
}

# Check through the rule symbol lists to see if any rules are missing.  If so,
# we'll create ATOM references for 'em.
print "\n\nChecking for references to missing rules\n";
my @new_atoms;
for my $rule (sort keys %$RULES) {
    for my $sym (sort keys %{$RULES->{$rule}{SYMS}}) {
        if (! exists $RULES->{$sym}) {
            print "Creating atomic rule '$sym'\n";
            push @new_atoms, $sym;
        }
    }
}

$RULES->{$_} = { ATOM=>1, CARD=>1, ROOT=>0, NAME=>$_, SYMS=>{} } for @new_atoms;


#########
# OK, here's were we do the share all thing.  What we want to do is:  First build
# an iterator graph, then review the share-all entries and mark all special nodes
# putting them into equivalence groups.  Once that's done, we want to build a
# poset graph and then figure out how to compute from it....
########

# Compute rule cardinality.  It's effectively done as a toposort, as we've already assigned
# atoms (rules with no dependencies) as having cardinality 1.  Each pass, we remove
# from each rules SYM list all rules having a cardinality.  If the rule has no SYMs left,
# we compute the cardinality, otherwise, we save the rule for next pass.

compute_cardinality;

#print pp($RULES), "\n\n";

##### Display the summary
# (the basic cardinality of the system (excluding the share all) is
# the product of the cardinality of the roots)
my $system_cardinality = 1;
for my $rule (sort keys %$RULES) {
    $system_cardinality *= $RULES->{$rule}{CARD} if $RULES->{$rule}{ROOT};
    next if $RULES->{$rule}{ATOM};
    printf "%-20.20s  %-5.5s %-5.5s % 8u\n", $rule,
    ($RULES->{$rule}{ATOM} ? "ATOM" : ""),
    ($RULES->{$rule}{ROOT} ? "ROOT" : ""),
    $RULES->{$rule}{CARD};
}

print "B <$system_cardinality>\n";
$system_cardinality = eng_not($system_cardinality);
print "C <$system_cardinality>\n";
print "System cardinality (excluding share all rules): $system_cardinality\n";

