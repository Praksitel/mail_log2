#!/usr/bin/perl

use strict;
use warnings FATAL => 'all';

use utf8;

package mail_log2;
use Dancer2;
use DateTime::Format::Pg;
use Email::Valid;
use DBD::Pg;

our $VERSION = '0.1';

my $flagMap = {
    '<=' => 'entering',
    '=>' => 'normal delivery',
    '->' => 'additional address',
    '**' => 'fail delivery',
    '==' => 'pause delivery',
};

my ($parsedLog, $dbh, $sth, $result, $output);
my ($logLoaded);

get '/' => sub {
    template 'index' => { 'title' => 'mail_log2' };
};

get '/parseLog' => sub {

    my $readStrings;

    if (defined $parsedLog) {
        $result = "Лог-файл уже распарсен";
    } else {
        $parsedLog = parseLog() ;
        $readStrings = scalar @{$parsedLog->{h}};
    }

    template 'index', {
        result => $parsedLog->{result},
        readStrings => $readStrings,
    };
};

get '/showFile' => sub {

    if (! defined $parsedLog) {
        $result = "Лог-файл не распарсен";
    } else {
        $output = [];

        for my $str (@{$parsedLog->{h}}) {
            push @$output, {
                datetime   => $str->{datetime},
                internalId => $str->{internalId},
                parsedFlag => $str->{parsedFlag},
                address    => $str->{address},
                info       => $str->{info},
            };
        }
    }

    template 'showLog', {
        result => $result,
        parsedLog => $output,
    };
};

get '/initDB' => sub {

    $result = initDB() if !defined $dbh;

    template 'index', {
        result => $result,
        dbhConnect => defined $dbh ? $dbh : undef,
    };
};

get '/logToDB' => sub {

    if (! defined $parsedLog) {
        $result = "Не найден распарсенный лог" ;
    } elsif (! defined $dbh) {
        $result = "Не установлено соединение с БД";
    } elsif (! defined $logLoaded) {
        $result = loadLogToDB();
    }

    template 'index', {
        result => $result,
    };
};

get '/showDB' => sub {

    ($result, my $log, my $message) = showDB();

    template 'showDBLog', {
        result  => $result,
        log     => $log,
        message => $message,
    };
};

any ['get', 'post'] => '/search' => sub {
    my $q = body_parameters->get('q');
    my ($message, $messages_count, $messages_excess);

    $result = "Ничего не найдено";

    if (! defined $dbh) {
        $result = "Не установлено соединение с БД";
    } else {
        if (defined $q) {
            ($result, $message, $messages_count) = searchInDB($q);
            $messages_excess = $messages_count if $messages_count > 100;
        }
    }

    template 'search', {
        result         => $result,
        message        => $message,
        messages_excess => $messages_excess,
    };
};

sub searchInDB {
    my $address = shift;

    my $message = [];
    my $messages_count;

    my $rc = Email::Valid->address($address);

    if (!defined $rc) {
        $result = "Введённый адрес невалиден: $address";
    } else {

        my $sql =<<SQL;
SELECT created, str
FROM (
    SELECT created, str, int_id
    FROM message
    WHERE int_id IN (SELECT int_id FROM log WHERE address=?)
    UNION ALL
    SELECT created, str, int_id
    FROM log
    WHERE address=?
) t
ORDER BY int_id::integer, created
SQL
        eval { $sth = $dbh->prepare($sql); };
        if ($@) {
            $result = "Ошибка в prepare: $@"
        } else {
            $result = undef;
            $sth->execute($address, $address);

            $messages_count = 0;
            while (my $fetch = $sth->fetchrow_hashref) {
                push @$message, $fetch if $messages_count < 100;
                ++$messages_count;
            }

        }

    }
    return ($result, $message, $messages_count);
}

sub loadLogToDB {
    my $sql_message =<<SQL;
INSERT INTO message VALUES (?,?,?,?)
SQL
    my $sql_log =<<SQL;
INSERT INTO log VALUES (?,?,?,?)
SQL
    my $sth_log = $dbh->prepare($sql_log);
    my $sth_message = $dbh->prepare($sql_message);
    my $retval;

    my $intNumbers = {};
    my $count = 1;

    $result = 'ok';

    for my $str (@{$parsedLog->{h}}) {
        $intNumbers->{$str->{internalId}} = $count++ if !exists $intNumbers->{$str->{internalId}};

        if ($str->{parsedFlag} eq 'entering') {
            my (@arr) = (
                $str->{datetime}
                , $str->{internalId}
                , $intNumbers->{$str->{internalId}}
                , $str->{str}
            );

            $retval = $sth_message->execute(@arr);

            if ($retval != 1) {
                $result = "Ошибка в execute: ";
                $result .= $sth_message->errstr() if $sth_message->err();
            }
        } else {
            my (@arr) = (
                $str->{datetime}
                , $intNumbers->{$str->{internalId}}
                , $str->{str}
                , $str->{address} ne 'no address' ? $str->{address} : undef
            );

            $retval = $sth_log->execute(@arr);

            if ($retval != 1) {
                $result = "Ошибка в execute: ";
                $result .= $sth_log->errstr() if $sth_log->err();
            }
        }

    }

    $dbh->commit();
    $logLoaded = 1;

    return $result;
}

sub initDB {
    my $db_name = 'mail_log';
    my $db_host = $db_name.'_db';
    my $connect = "DBI:Pg:dbname=$db_name;host=$db_host;port=5432";
    my $db_login = $db_name;
    my $db_pass = $db_name;
    my $options = {
        PrintError => 0
        , AutoCommit => 0
        , RaiseError => 1
        , pg_server_prepare => 0
    };

    eval { $dbh = DBI->connect($connect, $db_login, $db_pass, $options) };

    if ($@) {
        $result = $@;
    } else {
        $dbh->{pg_enable_utf8} = 1;

        $result = 'ok';
    }
    return $result;
}

sub showDB {
    my $log = [];
    my $message = [];

    if (! defined $dbh) {
        $result = "Не установлено соединение с БД";
    } elsif (! defined $logLoaded) {
        $result = "Лог не загружен в БД";
    } else {

        my $sql =<<SQL;
SELECT * FROM log
SQL
        eval { $sth = $dbh->prepare($sql); };
        if ($@) {
            $result = "Ошибка в prepare: $@"
        } else {
            eval { $sth->execute; };

            if ($@) {
                $result = "Ошибка в execute: $@"
            } else {
                while (my $fetch = $sth->fetchrow_hashref) {
                    push @$log, $fetch;
                }
            }
        }

        $sql =<<SQL;
SELECT * FROM message
SQL
        eval { $sth = $dbh->prepare($sql); };
        if ($@) {
            $result = "Ошибка в prepare: $@"
        } else {
            eval { $sth->execute; };

            if ($@) {
                $result = "Ошибка в execute: $@"
            } else {
                while (my $fetch = $sth->fetchrow_hashref) {
                    push @$message, $fetch;
                }
            }
        }
        $result = undef;
    }
    return ($result, $log, $message);
}

sub parseLog {
    my $fileName = param('file');
    my $logFile = "out";
    $fileName //= $logFile;

    $output = {
        h => [],
    };

    my (@errors);

    eval {open(FH, '<', $fileName)};

    if ($@) {
        $result = "Ошибка открытия файла: $@";
    } else {
        while (my $str = <FH>) {

            my (@fields) = split(' ' => $str);

            my $datetime = shift @fields;
            $datetime .= ' ';
            $datetime .= shift @fields;

            my $dt = eval {DateTime::Format::Pg->parse_datetime($datetime);};

            push @errors, "Error parsing datetime: $@" if $@;

            my $strToLog = join(' ' => @fields);

            my $internalId = shift @fields;
            my $flag = shift @fields;

            my $parsedFlag = $flagMap->{$flag};
            my ($address, $info);

            if (!defined $parsedFlag) {
                $parsedFlag = '<no flag>';
                unshift @fields, $flag;
                $info = join(' ' => @fields);
            }
            else {
                $address = shift @fields;
                $address =~ s/://;
                $address = Email::Valid->address($address) if $address ne '<>';

                $info = join(' ' => @fields);

                if (!defined $address) {
                    $address = $info =~ /(\S+\@\S+)/ ? $1 : 'not found';

                    if (defined $address) {
                        $address =~ s/<//;
                        $address =~ s/>//;
                        shift @fields;
                        $info = join(' ' => @fields);
                    }
                }
            }

            $address //= 'no address';

            push @{$output->{h}}, {
                datetime   => DateTime::Format::Pg->format_datetime($dt),
                internalId => $internalId,
                parsedFlag => $parsedFlag,
                address    => $address,
                info       => $info,
                str        => $strToLog,
            };
        }

        close FH;
    }

    $result .= join ("\n" => @errors) if scalar @errors;

    return ($result, $output);
}
true;