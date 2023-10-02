#!/usr/bin/perl

use strict;
use warnings;
use constant {
    FOOD_TRUCK_URL => 'http://data.sfgov.org/api/views/rqzj-sfat/rows.csv',
    TRUCK_DB_FILE => 'truck.sqlite',
};

use HTTP::Tiny;
use DBI;
use Text::CSV qw(csv);
use Geo::Calc;

#
# Completely ignoring the possibility of Unicode
#

sub load_csv {
    #
    # Fetch the current version of the SF food truck CSV, read it as a blob, and
    # parse into column names and rows.
    #
    print "Loading CSV at '" . FOOD_TRUCK_URL . "' ...\n";
    my $response = HTTP::Tiny->new->get(FOOD_TRUCK_URL);
    die "SF food truck URL GET '" . FOOD_TRUCK_URL . "' failed\n" unless $response->{success};

    print "... parsing ...\n";
    my $content = $response->{content};
    my $truck_csv = csv(in => \$content)
        or die "CSV parse failed.";

    my ($col_name, @rows) = @$truck_csv;

    #
    # Strip out nulls and other garbage from row data, should there be any.
    #
    for (@rows) {
        s/[\0-\037]// for @$_;
    }

    print "... creating database '" . TRUCK_DB_FILE . "' ...\n";
    #
    # Connect to (and create if necessary) the SQLite file.
    #
    my $dbh = DBI->connect("dbi:SQLite:dbname=" . TRUCK_DB_FILE, '', '');

    #
    # Column names in this data include things like spaces and punctuation, so
    # make them SQL-reasonable, then turn them into CREATE TABLE SQL.
    #
    for (@$col_name) {
        s/ /_/g;
        s/[\W^\r\n]//g;
        $_ = lc;
    }
    unshift @$col_name, 'row_id';
    my $col_sql = join ",\n", map {
        "$_ TEXT"
    } @$col_name;
    my $create_sql = qq(
        CREATE TABLE truck (
            $col_sql
        )
    );

    #
    # These inserts run a ton faster, like 100x, with AutoCommit disabled so let's do that.
    #
    $dbh->begin_work;
    $dbh->do('DROP TABLE IF EXISTS truck');
    $dbh->do($create_sql);

    my $placeholders = join ', ', ('?') x @$col_name;
    my $insert_sth = $dbh->prepare(qq(
        INSERT INTO truck
        VALUES ($placeholders)
    ));

    my $row_id = 1;
    for (@rows) {
        $insert_sth->execute($row_id++, @$_);
    }
    $dbh->commit;
    print "... done.\n";
    return $dbh;
}

sub calc_bearings_and_distances {
    my $dbh = shift;
    print "Now, be patient for a few seconds: Computing bearings and distances ...\n";
    #
    # Brute force what's basically a cross join for each pair of locations.
    # This SQLite doesn't have math extensions, but we need more than sqrt anyway.
    #
    my $lat_long = $dbh->selectall_arrayref(q(
        SELECT row_id, latitude lat, longitude lon
        FROM truck
        WHERE lower(status) = 'approved'
        AND latitude IS NOT NULL
        AND 0 + latitude <> 0
        AND longitude IS NOT NULL
        AND 0 + longitude <> 0
        ORDER BY 0 + row_id
    ));
    $dbh->begin_work;
    $dbh->do('DROP TABLE IF EXISTS dist_bearing');
    $dbh->do(q(
        CREATE TABLE dist_bearing (
            id_1 INT,
            id_2 INT,
            distance FLOAT,
            bearing FLOAT
        ))
    );

    my $insert_sth = $dbh->prepare(qq(
        INSERT INTO dist_bearing (id_1, id_2, distance, bearing)
        VALUES (?, ?, ?, ?)
    ));
    for my $l1 (@$lat_long) {
        my ($id_1, $lat_1, $lon_1) = @$l1;
        my $geo = Geo::Calc->new({ lat => $lat_1, lon => $lon_1 });
        for my $l2 (@$lat_long) {
            my ($id_2, $lat_2, $lon_2) = @$l2;
            next if $id_1 == $id_2;
            my $dist = $geo->distance_to({ lat => $lat_2, lon => $lon_2});
            my $bearing = $geo->bearing_to({ lat => $lat_2, lon => $lon_2});
            $insert_sth->execute($id_1, $id_2, $dist, $bearing);
        }
    }
    $dbh->commit;
    print "...done.\n";
}

my $dbh = load_csv();
calc_bearings_and_distances($dbh);

#
# Let's do some random nonsense ...
#
my $r = $dbh->selectall_arrayref(q(SELECT count(*) from truck));
my $all_count = $r->[0][0];

$r = $dbh->selectall_arrayref(q(SELECT count(*) FROM truck WHERE lower(status) = 'approved'));
my $approved_count = $r->[0][0];
$r = $dbh->selectall_arrayref(q(SELECT count(*) FROM truck WHERE lower(facilitytype) = 'truck' and lower(status) = 'approved'));
my $approved_truck = $r->[0][0];
$r = $dbh->selectall_arrayref(q(SELECT count(*) FROM truck WHERE lower(facilitytype) = 'push cart' and lower(status) = 'approved'));
my $approved_cart = $r->[0][0];

$r = $dbh->selectall_arrayref(q(SELECT count(distinct(id_1)) FROM dist_bearing));
my $with_location_count = $r->[0][0];

print <<END;

    Note: There are many caveats about this data, including that some carts are permitted for many, MANY
    more locations than they occupy. I couldn't find a way to distinguish "active" from "permitted."

    With that caveat, here are some random facts:

    Total of permits: $all_count
    Approved permits: $approved_count
    Approved truck permits: $approved_truck
    Approved cart permits: $approved_cart
    Permits with a (lat, long) location: $with_location_count

END

#
# Something mildly interesting
#
$r = $dbh->selectall_arrayref(q(
    WITH nexus (row_id, n) AS (
        SELECT row_id, count(*) n
        FROM truck, dist_bearing
        WHERE truck.row_id = dist_bearing.id_1
        AND dist_bearing.distance < 250 --meters
        GROUP BY row_id
        ORDER BY n DESC
        LIMIT 1
    )
    SELECT NULL, NULL, t1.* FROM truck t1, nexus
    WHERE t1.row_id = nexus.row_id
    UNION
    SELECT distance, bearing, t2.* FROM truck t1, nexus, dist_bearing, truck t2
    WHERE t1.row_id = nexus.row_id
    AND t1.row_id = dist_bearing.id_1
    AND t2.row_id = dist_bearing.id_2
    AND dist_bearing.distance < 250
    ORDER BY distance
));
print "EXTRA CREDIT:\n";
print "What approved truck (or cart) permit has the most approved permits within 250 meters?\n";
print "\n";
print "The winner:\n";
print "  $r->[0][4] at $r->[0][8] $r->[0][14]\n";
print "\n";
print "And the permits within 250 meters:\n";
shift @$r;
for (@$r) {
    printf "%4d m  %3d deg  %s  %s %s\n", $_->[0], $_->[1], $_->[4], $_->[8], $_->[14];
}
print "\n";
print "Use your favorite SQLite client to play with the database file at '" . TRUCK_DB_FILE . "'.\n";
print "Have fun!\n";