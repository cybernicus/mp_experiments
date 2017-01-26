#!/usr/bin/env perl
#
#   mp_cheezparse.pm
#
#   cheesy MP parser
#
package mp_cheezparse;

use strict;
use warnings;
use Data::Dump 'pp';
use MCMUtils;

use Exporter qw(import);
use Data::Dump qw(pp);

our @EXPORT = qw(
    tokenize
    statementize
    parse
    parse_rule
    compute_cardinality
    cardinality
);

our %RULES;
our $scope=3;

##### split the tokens into statement groups (on semicolon) #####
sub statementize {
    my @tokens = @_;
    my @stmts = ([]);
    for my $T (@tokens) {
        if ($T->[0] eq 'EOSTMT') {
            # Start a new statement token list
            push @stmts, [];
        }
        else {
            push @{$stmts[-1]}, $T;
        }
    }
    return @stmts;
}

sub parse {
    my @stmts = @_;
    for my $rS (@stmts) {
        my @S = @$rS;
        next unless @S;
        #print "\n----------\nParsing: ", pp(\@S), "\n";
        if ($rS->[0][0] ne 'SYM') {
            print "X: ", pp($rS), "\n";
            die "Unexpected!";
        }

        if ($S[0][1] eq 'ROOT') {
            # New root
            shift @S;
            my $t = parse_rule(@S);
            $t->{ROOT}=1;
            $RULES{$t->{NAME}} = $t;
        }
        elsif ($S[1][0] eq 'COLON') {
            # New rule
            my $t = parse_rule(@S);
            $t->{ROOT}=0;
            $RULES{$t->{NAME}} = $t;
        }
        elsif ($S[1][0] eq 'COMMA') {
            # New share all?
            print "??? SHARE ALL ???\n";
        }
        else {
            print "<<< ", pp($rS), ">>>\n";
            die "Eh?";
        }
    }

    return \%RULES;
}

sub create_missing_atoms {
    # Check through the rule symbol lists to see if any rules are missing.  If so,
    # we'll create ATOM references for 'em.
    print "\n\nChecking for references to missing rules\n";
    my @new_atoms;
    for my $rule (sort keys %RULES) {
        for my $sym (sort keys %{$RULES{$rule}{SYMS}}) {
            if (! exists $RULES{$sym}) {
                print "Creating atomic rule '$sym'\n";
                push @new_atoms, $sym;
            }
        }
    }
    $RULES{$_} = { ATOM=>1, CARD=>1, ROOT=>0, NAME=>$_, SYMS=>{} } for @new_atoms;
}


sub compute_cardinality {
    # Compute rule cardinality.  It's effectively done as a toposort, as we've already assigned
    # atoms (rules with no dependencies) as having cardinality 1.  Each pass, we remove
    # from each rules SYM list all rules having a cardinality.  If the rule has no SYMs left,
    # we compute the cardinality, otherwise, we save the rule for next pass.

    my $chgs = 1; #force first pass
    my $pass = 0;
    while ($chgs) {
        $chgs = 0;
        my @rules_to_check = grep { ! exists $RULES{$_}{CARD} } keys %RULES;
        last if !@rules_to_check;

        ++$pass;
        print "\n\n", "*"x80, "\n";
        print "Pass $pass: RULES TO CHECK: ", join(", ", @rules_to_check), "\n";

        for my $rule (@rules_to_check) {
            my @deps = sort keys %{$RULES{$rule}{SYMS}};
            if (@deps) {
                print "\nRULE $rule: ", scalar(@deps), " dependencies\n";
                my @tmp = grep { exists $RULES{$_}{CARD} } keys %RULES;
                delete @{$RULES{$rule}{SYMS}}{@tmp};
                @deps = sort keys %{$RULES{$rule}{SYMS}};
            }
            if (@deps) {
                print "\tAfter check, ", scalar(@deps), " remain, try again next pass\n";
                next;
            }
            else {
                print "\tAll cleared!\n";
            }
            $RULES{$rule}{CARD} = cardinality($rule);
            ++$chgs;
        }
        print "*** $chgs ***\n\n";
    }
}

sub display_cardinality_summary {
    ##### Display the summary
    # (the basic cardinality of the system (excluding the share all) is
    # the product of the cardinality of the roots)
    my $system_cardinality = 1;
    for my $rule (sort keys %RULES) {
        $system_cardinality *= $RULES{$rule}{CARD} if $RULES{$rule}{ROOT};
        next if $RULES{$rule}{ATOM};
        printf "%-20.20s  %-5.5s %-5.5s % 8u\n", $rule,
        ($RULES{$rule}{ATOM} ? "ATOM" : ""),
        ($RULES{$rule}{ROOT} ? "ROOT" : ""),
        $RULES{$rule}{CARD};
    }
    $system_cardinality = eng_not($system_cardinality);
    print "System cardinality (excluding share all rules): $system_cardinality\n";
}


sub tokenize {
    my $T = shift;
    my @tokens = ();

    while ($T ne '') {
        $T=~/^\s+(.*)/ && do { $T=$1; next };
        $T=~/^([A-Za-z][A-Za-z0-9_]*)(.*)/ && do { $T=$2; push @tokens, [ 'SYM', $1 ]; next };
        $T=~/^(:)(.*)/ && do { $T=$2; push @tokens, [ 'COLON', $1 ]; next };
        $T=~/^(;)(.*)/ && do { $T=$2; push @tokens, [ 'EOSTMT', $1 ]; next };
        $T=~/^(,)(.*)/ && do { $T=$2; push @tokens, [ 'COMMA', $1 ]; next };
        $T=~/^({)(.*)/ && do { $T=$2; push @tokens, [ 'SET', $1 ]; next };
        $T=~/^(})(.*)/ && do { $T=$2; push @tokens, [ 'SETEND', $1 ]; next };
        $T=~/^(\(\*)(.*)/ && do { $T=$2; push @tokens, ['RPT', $1 ]; next };
        $T=~/^(\*\))(.*)/ && do { $T=$2; push @tokens, ['RPTEND', $1 ]; next };
        $T=~/^(<[0-9]+>)(.*)/ && do { $T=$2; push @tokens, ['PROB', $1 ]; next };
        $T=~/^(<[0-9]+\.[0-9]*>)(.*)/ && do { $T=$2; push @tokens, ['PROB', $1 ]; next };
        $T=~/^(<[0-9]*>\.[0-9]+>)(.*)/ && do { $T=$2; push @tokens, ['PROB', $1 ]; next };
        # doesn't work: cheesed it at end
        #$T=~m{^(<[-0-9/.,]+>)(.*)} && do { $T=$2; push @tokens, ['PROBS', $1 ]; next };
        $T=~/^(\()(.*)/ && do { $T=$2; push @tokens, ['ALTBEG', $1 ]; next };
        $T=~/^(\))(.*)/ && do { $T=$2; push @tokens, ['ALTEND', $1 ]; next };
        $T=~/^(\|)(.*)/ && do { $T=$2; push @tokens, ['ALT', $1 ]; next };

        # Cheese
        $T=~m{^(<.+?>)(.*)} && do { $T=$2; push @tokens, ['PROB', $1 ]; next };
        print "[ $_->[0], $_->[1] ]\n" for @tokens;
        die "Ugh! <" . substr($T,0,25);
    }
    return @tokens;
}

sub parse_rule {
    my ($name, @t) = @_;

    my $rv = { NAME=> $name->[1] };
    die "Expected COLON after rule name ($name->[1])\n"
        unless $t[0][0] eq 'COLON';
    shift @t;

    cnt(PARSE);

    # Essentially, everything is an implicit SEQUENCE, and we just need to maintain a
    # stack of contexts to push sequences and events into.  Each time we hit an operator
    # verify the TOS and do the thing.

    # If we get set, rpt, altbeg or alt, we push a context onto the stack.  If we get
    # to an end (alt, altend, rptend, setend) we pop the context off the stack, and add
    # it to the end of the new TOS.
    #
    my @stack = ([]);
    while (scalar @t) {
        my $tk = shift @t;
        #print "--- tk ($tk->[0]; $tk->[1]), TOS:", pp($stack[-1]), "\n";
        if ($tk->[0] eq 'RPT') {
            push @stack, [ 'RPT' ];
        }
        elsif ($tk->[0] eq 'RPTEND') {
            print "Mismatched context (RPT context expected)", last if $stack[-1][0] ne 'RPT';
            my $tmp = pop @stack;
            push @{$stack[-1]}, $tmp;
        }
        elsif ($tk->[0] eq 'SET') {
            push @stack, [ 'SET' ];
        }
        elsif ($tk->[0] eq 'SETEND') {
            print "Mismatched context (SET context expected)", last if $stack[-1][0] ne 'SET';
            my $tmp = pop @stack;
            push @{$stack[-1]}, $tmp;
        }
        elsif ($tk->[0] eq 'ALTBEG') {
            # push the alt wrapper onto the stack, then the first alternation context
            push @stack, [ 'ALT' ], [];
        }
        elsif ($tk->[0] eq 'ALT') {
            # Yes, it's -2 here, as the current TOS is expected to be the seq for the
            # current alternation.  So finish current alternation, wrap it into the
            # alt context, then start context for next alt
            print "Mismatched context (ALT context expected)", last if $stack[-2][0] ne 'ALT';
            my $tmp = pop @stack;
            push @{$stack[-1]}, $tmp;
            push @stack, [];
        }
        elsif ($tk->[0] eq 'ALTEND') {
            # End of alternation.  Close current alternation, wrap it into the alt.
            # Then end the alternation block and wrap it into the upper level.
            print "Mismatched context (ALT context expected (END))", last if $stack[-2][0] ne 'ALT';
            my $tmp = pop @stack;
            push @{$stack[-1]}, $tmp;
            $tmp = pop @stack;
            push @{$stack[-1]}, $tmp;
        }
        elsif ($tk->[0] eq 'PROB') {
            # We don't care about them for now
        }
        else {
            if ($tk->[0] eq 'SYM') {
                # make sure we know what symbols are used, for topo-sort and cardinality
                $rv->{SYMS}{$tk->[1]} = 0;
            }
            push @{$stack[-1]}, $tk;
        }
    }

    if (1 != scalar @stack) {
        $rv->{UNG} = [ @stack ];
        die "UNG!" . pp($rv);
    }
    else {
        if (0 == scalar(@{$stack[0]})) {
            $rv->{ATOM} = 1;
            $rv->{CARD} = 1;
            delete $rv->{SYMS};
        }
        else {
            $rv->{PROD} = $stack[0];
            $rv->{ATOM} = 0;
        }
    }

    if (@t) {
        $rv->{REST} = [@t];
        cnt(FAULTS);
    }

    #print "stmt: ", pp($rv), "\n";
    return $rv;
}

sub cmp_card {
    my $ar = shift;
    if ("" eq ref $ar->[0]) {
        if ($ar->[0] eq 'ALT') { return cmp_alt($ar); }
        if ($ar->[0] eq 'SET') { return cmp_set($ar); }
        if ($ar->[0] eq 'RPT') { return cmp_rpt($ar); }
        if ($ar->[0] eq 'SYM') { return $RULES{$ar->[1]}{CARD}; }
    }
    if ("ARRAY" eq ref $ar->[0]) {
        my $rv = 1;
        $rv *= cmp_card($_) for @$ar;
        return $rv;
    }

    die "WTF?";
}

sub cmp_alt {
    my $ar = shift;
    # An ALT is simply the cardinality of the sum of the cardinality of its branches
    my $rv = 0;
    $rv += cmp_card($ar->[$_]) for 1 .. $#$ar;
    return $rv;
}

sub cmp_rpt {
    my $ar = shift;
    # Repeat is a loop, so we repeat the body from 0 to scope
    my $rv = 1;
    $rv *= cmp_card($ar->[$_]) for 1 .. $#$ar;
    my $accum = 1; # for 0 repeats
    my $tmp = 1; # start
    for (1 .. $scope) {
        $tmp *= $rv;
        $accum += $tmp;
    }
    return $accum;
}

sub cmp_set {
    my $ar = shift;
    # set is like sequence: product of components
    my $rv = 1;
    $rv *= cmp_card($ar->[$_]) for 1 .. $#$ar;
    return $rv;
}

sub cardinality {
    my $rule = shift;

    return $RULES{$rule}{CARD} if exists $RULES{$rule}{CARD};
    return 999999999 if ! exists $RULES{$rule}{PROD};

    
    $RULES{$rule}{CARD} = cmp_card($RULES{$rule}{PROD});
    if ($RULES{$rule}{CARD} < 0) {
        print "BAD CARDINALITY: ", pp($RULES{$rule}), "\n";
        die;
    }
    return $RULES{$rule}{CARD};
}

