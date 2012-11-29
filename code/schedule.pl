#!/usr/bin/perl
# author: Li Yang
# info: Help to calculate and print specific month work schedule for hospital

use warnings;
use strict;
use POSIX;
use File::Basename;
use File::Spec;
use Cwd;
use Spreadsheet::WriteExcel;
use utf8;

# set params
my $year = shift @ARGV || 2012;
my $month = shift @ARGV || 1;
my $export_xlsname = shift @ARGV || '';
my $showlog = shift @ARGV || 0;

&log(4, "Year: $year, Month: $month\n");

sub log() {
    my $lv = shift;
    print @_ if $lv <= $showlog;
}

sub logf() {
    my $lv = shift;
    printf @_ if $lv <= $showlog;
}

sub init_monthes() {
    my $y = shift() - 1900;
    my $m = shift() - 1;
    my %monthes = (year => $y + 1900, month => $m + 1);

    my $num_day = (localtime(POSIX::mktime(0, 0, 0, 0, $m + 1, $y)))[3];
    foreach (1..$num_day) {
	my $wday = (localtime(POSIX::mktime(0, 0, 0, $_, $m, $y)))[6];
	%{$monthes{days}{$_}} = (
	    day => $_,
	    wday => $wday,
	    m => [],
	    d => [],
	    n => [],
	    );

	$monthes{stat}{nf}++ if ($wday == 0 || $wday == 6);
    }

    $monthes{stat}{nm} = $num_day;
    $monthes{stat}{nd} = $num_day * 2;
    $monthes{stat}{nn} = $num_day;
    $monthes{stat}{np} = $num_day * 4;

    return %monthes;
}

sub init_workers() {
    my %workers = ();

    my $path = shift;
    die "Worker file $path doesn't exist." if not -e $path;
    
    open WORKER, "<$path";
    while (<WORKER>) {
	chomp;
	next if /^(#.*)?$/;

	my @items = split /,/;
	my @flags = @items[2..$#items-1];

	while (my ($idx, $it) = each(@flags)) {
	    $workers{$items[0]}{fflag} |= $it << $idx;
	}

	$workers{$items[0]}{name} = $items[0];
	$workers{$items[0]}{chinesename} = $items[1];
	$workers{$items[0]}{min_freeday} = $items[-1];
	$workers{$items[0]}{a} = 0;
	$workers{$items[0]}{d} = 0;
	$workers{$items[0]}{m} = 0;
	$workers{$items[0]}{n} = 0;
	$workers{$items[0]}{wd} = 0;
	$workers{$items[0]}{f} = 0;
    }
    
    close WORKER;

    return %workers;
}

sub init_environment() {
    my ($workers, $month) = (shift, shift);
    
    my $nworker = values %$workers;
    my $nlworker = 0;
    foreach (values %$workers) {
	$nlworker++ if ($_->{fflag} & 0b111111100000001111111);
    }
    my $ndworker = $nworker - $nlworker;

    &log(4, "Environment:\n");
    &log(4, "\tNumber of workers $nworker = (D)$ndworker + (L)$nlworker\n");

    return if $nworker <= 0 || $nlworker <= 0;

    $month->{stat}{ap} = $month->{stat}{np} / $nworker;
    
    $month->{stat}{adm} = 0;
    $month->{stat}{add} = $month->{stat}{ap};
    $month->{stat}{adn} = 0;
    
    $month->{stat}{alm} = $month->{stat}{nm} / $nlworker;
    $month->{stat}{ald} = ($month->{stat}{nd} - $month->{stat}{add} * $ndworker) / $nlworker;
    $month->{stat}{aln} = $month->{stat}{nn} / $nlworker;

    &log(4, "\tWorks:\n");
    &log(4, "\t\tNumber of freeday: $month->{stat}{nf}\n");
    &log(4, "\t\tNumber: $month->{stat}{np} = ".
	 "$month->{stat}{nm} + $month->{stat}{nd} + $month->{stat}{nn}\n");
    &logf(4, "\t\tAverage: %.2f\n", $month->{stat}{ap});
    &logf(4, "\t\tAverage for day time worker: (M)%.2f / (D)%.2f / (N)%.2f\n",
	  $month->{stat}{adm}, $month->{stat}{add}, $month->{stat}{adn});
    &logf(4, "\t\tAverage for loop worker: (M)%.2f / (D)%.2f / (N)%.2f\n",
	  $month->{stat}{alm}, $month->{stat}{ald}, $month->{stat}{aln});
}

sub print_table() {
    my $head = shift;
    my $rows = shift;
    my $al = shift; # 0: left, 1: right, 2: center
    my $nspace = shift;

    my $cw = 0; # column width
    foreach (@$rows) {
	foreach (@$_) {
	    my $l = length($_);
	    $cw = $l if ($cw < $l);
	}
    }

    my $space = " " x $nspace;
    my $itemf = ($al == 1) ? "%-${cw}s" : "%${cw}s";

    printf join("|", ("$space$itemf$space") x @$head)."\n", @$head;
    print join("+", ("-" x ($nspace + $cw + $nspace)) x @$head)."\n";
    foreach (@$rows) {
	if (@$_ > 0) {
	    printf join("|", ("$space$itemf$space") x @$_)."\n", @$_;
	} else {
	    print join("+", ("-" x ($nspace + $cw + $nspace)) x @$head)."\n";
	}
    }
}

sub export_table() {
    my $head = shift;
    my $rows = shift;
    my $filename = shift;

    my $path = File::Spec->catfile(getcwd(), $filename);
    &log(0, "Export Table to $path\n");

    my $book = Spreadsheet::WriteExcel->new($path);
    my $schedulesheet = $book->add_worksheet('schedule');

    unshift @$rows, $head;

    while (my ($row, $cols) = each(@$rows)) {
	while (my ($col, $it) = each(@$cols)) {
	    $schedulesheet->write($row, $col, $it,
				  $book->add_format(bg_color => $col % 2 ? 'gray' : 'white'));
	}
    }
}

sub print_schedule() {
    my ($month, $workers) = (shift, shift);
    
    my @head = qw / Name Sun Mon Tue Wed Thu Fri Sat /;
    my @table = ();

    my $monthes = $month->{days};
    my @workers = sort {$a->{name} cmp $b->{name}} values %$workers;
    my $daterowidx = 0;
    my @rowindices = ();

    my $dw = 2; # date width
    
    my @days = sort {$a <=> $b} keys(%$monthes);

    foreach (@days) {
	my $day = $_;
	my $info = $monthes->{$_};

	my $newline = 0;
	$newline = 1 if ($info->{wday} == 0) || ($day == $days[0]);
	
	push @{$table[$#table+1]}, () if $newline && $day != $days[0]; # line

	# date line
	if ($newline) {
	    $daterowidx = $#table + 1;
	    push @{$table[$daterowidx]}, ('');
	}

	push @{$table[$daterowidx]}, ("") x $info->{wday} if ($day == $days[0]);
	push @{$table[$daterowidx]}, $info->{day};
	push @{$table[$daterowidx]}, ("") x (6 - $info->{wday}) if ($day == $days[-1]);

	# schedule content lines
	while (my ($idx, $worker) = each (@workers)) {
	    if ($newline) {
		$rowindices[$idx] = $#table+1;
		push @{$table[$#table+1]}, ($worker->{name});
	    }

	    my $row = $rowindices[$idx];
	    
	    push @{$table[$row]}, ("") x $info->{wday} if ($day == $days[0]);

	    my $daywork = &get_daywork($worker, $day);
	    my $dayworkname = '';
	    $dayworkname .= 'M' if ($daywork & 4);
	    $dayworkname .= 'D' if ($daywork & 2);
	    $dayworkname .= 'N' if ($daywork & 1);
	    $dayworkname .= 'F' if $dayworkname eq '';

	    push @{$table[$row]}, $dayworkname;

	    push @{$table[$row]}, ("") x (6 - $info->{wday}) if ($day == $days[-1]);
	}
    }

    print "Table: Schedule $month->{year}/$month->{month}\n";
    &print_table(\@head, \@table, 1, 1);

    # replace for xls export
    foreach (@table) {
	foreach (@$_) {
	    s/^M$/出/;
	    s/^D$/白/;
	    s/^N$/夜/;
	    s/^F$/休/;
	    s/^Sun$/日/;
	    s/^Mon$/一/;
	    s/^Tue$/二/;
	    s/^Wed$/三/;
	    s/^Thu$/四/;
	    s/^Fri$/五/;
	    s/^Sat$/六/;
	    s/^Name$/姓名/;
	    if (exists $workers->{$_}) {
		s/^$_$/$workers->{$_}{chinesename}/;
		utf8::decode($_);
	    }
	}
    }
    
    &export_table(\@head, \@table, $export_xlsname) if $export_xlsname;
}

sub print_stat() {
    my ($month, $workers) = (shift, shift);
    
    my @head = qw / Name M D N Work Free /;
    my @rows = ();

    # total stat
    push @{$rows[$#rows+1]}, ('month',
			      $month->{stat}{nm},
			      $month->{stat}{nd},
			      $month->{stat}{nn},
			      $month->{stat}{np},
			      $month->{stat}{nf});
    
    push @{$rows[$#rows+1]}, ();

    # aver stat
    push @{$rows[$#rows+1]}, ('average d',
			      sprintf("%.2f", $month->{stat}{adm}),
			      sprintf("%.2f", $month->{stat}{add}),
			      sprintf("%.2f", $month->{stat}{adn}),
			      '', '');
    
    push @{$rows[$#rows+1]}, ('average l',
			      sprintf("%.2f", $month->{stat}{alm}),
			      sprintf("%.2f", $month->{stat}{ald}),
			      sprintf("%.2f", $month->{stat}{aln}),
			      '', '');

    push @{$rows[$#rows+1]}, ();
    
    # workers stat
    foreach (sort {$a->{name} cmp $b->{name}} values %$workers) {
	push @{$rows[$#rows+1]}, ($_->{name},
				  $_->{m},
				  $_->{d},
				  $_->{n},
				  $_->{a},
				  $_->{f});
    }
    
    print "Table: Statistic $month->{year}/$month->{month}\n";
    &print_table(\@head, \@rows, 1, 1);
}

sub print_worker() {
    my $lv = shift;
    my $n = shift;
    my $indent = "\t" x $n;
    &log($lv, "${indent}Workers ".@_.": \n");
    while (my ($idx, $_) = each(@_)) {
	&log($lv, "${indent}\t$idx:\n");
	&logf($lv, "${indent}\t\t%15s: %021b\n", "fflag", $_->{fflag});
	while (my ($k, $v) = each(%$_)) {
	    next if $k =~ /fflag/;
	    &logf($lv, "${indent}\t\t%15s: $v\n", $k);
	}
    }
}

sub print_day() {
    my $lv = shift;
    my $n = shift;
    my $indent = "\t" x $n;
    &log($lv, "${indent}Days ".@_.": \n");
    while (my ($idx, $_) = each(@_)) {
	&log($lv, "${indent}\t$idx:\n");
	while (my ($k, $v) = each(%$_)) {
	    if ($k =~ /^(m|d|n)$/) {
		&log($lv, "${indent}\t$k: @$v\n");
	    } else {
		&log($lv, "${indent}\t$k: $v\n");
	    }
	}
    }
}

# init environment
my %monthes = &init_monthes($year, $month);

my $dir = dirname(File::Spec->rel2abs($0));
my %workers = &init_workers(File::Spec->catfile($dir, "workers.csv"));

&init_environment(\%workers, \%monthes);

# Test workers init
&log(4, "Workers: \n");
&logf(4, "\tFLAG => %07b%07b%07b\n", 1, 1, 1);
while (my ($name, $info) = each(%workers)) {
    &log(4, "Name: $name\n");

    &logf(4, "\tflag => %021b\n", $info->{fflag});

    while (my ($k, $v) = each(%$info)) {
	next if $k eq 'fflag';
	&log(4, "\t$k => $v\n");
    }
}

sub set_worker() {
    my $workers = shift || [];
    my $day = shift;
    my $part = shift;

    &log(3, "Set Worker Parameters:\n");
    &print_worker(3, 1, @$workers);
    &print_day(3, 1, $day);
    &log(3, "\tPart: $part\n");

    foreach my $worker (@{$workers}) {
	if ($part =~ /m|d|n/) {
	    $worker->{$part}++;
	    $worker->{a}++;
	    push @{$day->{$part}}, $worker;
	} else {
	    &log(4, "Invalid part: $part\n");
	}
    }
}

sub get_daywork() {
    my $worker = shift;
    my $nday = shift || 0;

    return 0 if $nday < 1;
    
    my $day = $monthes{days}{$nday};

    my $result = 0;

    $result |= 4 if grep { $worker->{name} eq $_->{name} } @{$day->{m}};
    $result |= 2 if grep { $worker->{name} eq $_->{name} } @{$day->{d}};
    $result |= 1 if grep { $worker->{name} eq $_->{name} } @{$day->{n}};

    return $result;
}

sub select_worker() {
    my $workers = shift;
    my $day = shift;
    my $part = shift;
    my $num_workers = shift;
    my $available_conds = shift;
    my $weight_cals = shift;

    &log(3, "Select Worker Params:\n");
    &print_worker(3, 1, @$workers);
    &print_day(3, 1, $day);
    &log(3, "\tPart: $part\n");
    &log(3, "\tNumber of workers: $num_workers\n");
    &log(3, "\tAvailable Conditions: \n");
    while (my ($k, $v) = each(%$available_conds)) {
    	&log(3, "\t\t$k => $v\n");
    }
    &log(3, "\tWeight Calculations: \n");
    while (my ($k, $v) = each(%$weight_cals)) {
    	&log(3, "\t\t$k => $v\n");
    }

    my @available_workers = ();

    &log(2, "Select workers for '$part':\n");
    foreach my $worker (@$workers) {
	&log(2, "\tWorker '$worker->{name}':\n");
	&log(2, "\t\tIs available:\n");
	# filter not possible worker
	my $is_available = 1;
	keys %$available_conds; # reset each iterator
	while (my ($name, $fn) = each(%$available_conds)) {
	    $is_available = &$fn($day, $worker, $part);
	    &log(2, "\t\t\t$name = $is_available\n");
	    last if !$is_available;
	}
	next if !$is_available;

	&log(2, "\t\tCalculate Weight:\n");
	# calculate weight
	$worker->{wd} = 0;
	keys %$weight_cals; # reset each iterator
	while (my ($name, $fn) = each (%$weight_cals)) {
	    my $weight = &$fn($day, $worker, $part);
	    &logf(2, "\t\t\t$name : + %.2f = ", $weight);
	    $worker->{wd} += $weight;
	    &logf(2, "%.2f\n", $worker->{wd});
	}
	&logf(2, "\t\tWeight = %.2f\n", $worker->{wd});

	push @available_workers, $worker;
    }

    @available_workers = sort { $b->{wd} <=> $a->{wd} } @available_workers;
    &log(2, "\tAvailable workers: ".join(' ', map {$_->{name}} @available_workers)."\n");
    if (@available_workers) {
	my @w = @available_workers[0..$num_workers-1];
	&log(2, "\tSelected workers $num_workers: ".join(' ', map {$_->{name}} @w)."\n");
	&set_worker(\@w, $day, $part);
    } else {
	&log(0, "No perfect $part worker for $day->{day}\n");
    }
}

sub day_pass() {
    my $day = shift;
    
    # count worker's free day
    foreach (values %workers) {
	$_->{f}++ if not &get_daywork($_, $day->{day});
    }
}

# worker filter
sub is_rulepossible() {
    my ($day, $worker, $part) = (shift, shift, shift);
    my %m = ( m => 0, d => 7, n => 14 );
    
    (1 << ($m{$part} + $day->{wday}) & $worker->{fflag}) > 0;
}

sub is_noworktoday() {
    my ($day, $worker) = (shift, shift);
    
    &get_daywork($worker, $day->{day}) == 0;
}

# weight calculater
sub wt_onlydaytime() {
    my ($day, $worker) = (shift, shift);
    
    if (!($worker->{fflag} & 0b111111100000001111111)) {
	1;
    } else {
	0;
    }
}

sub wt_freeday() {
    my ($day, $worker) = (shift, shift);
    $worker->{f};
}

sub wt_nowork_lastday() {
    my ($day, $worker) = (shift, shift);

    if (&get_daywork($worker, $day->{day} - 1) == 0) {
	1;
    } else {
	0;
    }
}

sub wt_nightwork_lastday() {
    my ($day, $worker) = (shift, shift);

    if (&get_daywork($worker, $day->{day} - 1) & 1) {
	1;
    } else {
	0;
    }
}

sub wt_morningwork_lastday() {
    my ($day, $worker) = (shift, shift);

    if (&get_daywork($worker, $day->{day} - 1) & 0b100) {
	-1;
    } else {
	0;
    }
}

sub wt_leftworkday() {
    my ($day, $worker, $part) = (shift, shift, shift);

    if ($worker->{fflag} & 0b111111100000001111111) {
	$monthes{stat}{'al'.$part} - $worker->{$part};
    } else {
	$monthes{stat}{'ad'.$part} - $worker->{$part};
    }
}

# set work schedule
foreach (sort { $a->{day} <=> $b->{day} } values %{$monthes{days}}) {
    &log(2, "Begin Day $_->{day}.\n");

    my @workers = values %workers;

    my %conds = (rule => \&is_rulepossible,
		 nowork => \&is_noworktoday);
    my %cals = (nightwork_lastday => \&wt_nightwork_lastday,
		leftworkday => \&wt_leftworkday);
    &select_worker(\@workers, $_, 'm', 1, \%conds, \%cals);

    %conds = (rule => \&is_rulepossible,
	      nowork => \&is_noworktoday);
    %cals = (onlydaytime => \&wt_onlydaytime,
	     freeday => \&wt_freeday,
	     nowork_lastday => \&wt_nowork_lastday,
	     leftworkday => \&wt_leftworkday,
	     morningwork_lastday => \&wt_morningwork_lastday);
    &select_worker(\@workers, $_, 'd', 2, \%conds, \%cals);

    %conds = (rule => \&is_rulepossible,
	      nowork => \&is_noworktoday);
    %cals = (freeday => \&wt_freeday,
	     nowork_lastday => \&wt_nowork_lastday,
	     leftworkday => \&wt_leftworkday,
	     morningwork_lastday => \&wt_morningwork_lastday);
    &select_worker(\@workers, $_, 'n', 1, \%conds, \%cals);
    
    &day_pass($_);
    
    &log(2, "End Day $_->{day}.\n");
}

# result
&print_schedule(\%monthes, \%workers);
&print_stat(\%monthes, \%workers);
