# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

my $Helper       = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

my $Home = $Kernel::OM->Get('Kernel::Config')->Get('Home');

my @DatabaseXMLFiles = (
    "$Home/scripts/test/sample/DBUpdate/otrs5-schema.xml",
    "$Home/scripts/test/sample/DBUpdate/otrs5-initial_insert.xml",
);

my $Success = $Helper->ProvideTestDatabase(
    DatabaseXMLFiles => \@DatabaseXMLFiles,
);
if ( !$Success ) {
    $Self->False(
        0,
        'Test database could not be provided, skipping test'
    );
    return 1;
}
$Self->True(
    $Success,
    'ProvideTestDatabase - Load and execute XML files'
);

# Run preparation for this test
my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

# Check tables are not present before migration script
my @Tables = $DBObject->ListTables();

my @OldTablesName = ( 'article',           'article_plain',           'article_attachment' );
my @NewTablesName = ( 'article_data_mime', 'article_data_mime_plain', 'article_data_mime_attachment' );

my %CurrentTables = map { lc($_) => 1 } @Tables;

# Old tables should exist and new ones not yet.
for my $TableName (@OldTablesName) {
    $Self->True(
        $CurrentTables{$TableName},
        "Table $TableName is present in database!",
    );
}

# New tables shouldn't exist.
for my $TableName (@NewTablesName) {
    $Self->False(
        $CurrentTables{$TableName},
        "Table $TableName is not present in database!",
    );
}

# Load the upgrade XML file.
my $XMLString = $Kernel::OM->Get('Kernel::System::Main')->FileRead(
    Location => "$Home/scripts/database/update/otrs-upgrade-to-6.xml",
);

# Execute the the upgrade XML file.
$Helper->DatabaseXMLExecute(
    XML => ${$XMLString},
);

# Get new tables list.
@Tables = $DBObject->ListTables();
%CurrentTables = map { lc($_) => 1 } @Tables;

# Old tables should not exist any more
OLDTABLES:
for my $TableName (@OldTablesName) {

    # New article table should exist.
    next OLDTABLES if $TableName eq 'article';

    $Self->False(
        $CurrentTables{$TableName},
        "Table $TableName is not present in database!",
    );
}

# New article table should exist.
push @NewTablesName, 'article';

# New tables might exist in database.
for my $TableName (@NewTablesName) {
    $Self->True(
        $CurrentTables{$TableName},
        "Table $TableName is present in database!",
    );
}

# Init real test.
# On previous step article table was renamed
# then in next step a new article table and
# communication_channel table should be created

my $CheckData = sub {
    my %Param = @_;

    my $Test     = $Param{Test};
    my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

    my %TablesData = (
        'article' => {
            MaxID => 0,
            Count => 0,
        },
        'article_data_mime' => {
            MaxID => 0,
            Count => 0,
        },
    );

    for my $TableName ( sort keys %TablesData ) {

        # Get last id.
        return if !$DBObject->Prepare(
            SQL => "SELECT MAX(id) FROM $TableName",
        );
        while ( my @Row = $DBObject->FetchrowArray() ) {
            $TablesData{$TableName}->{MaxID} = $Row[0] || 0;
        }

        # Get amount of entries
        return if !$DBObject->Prepare(
            SQL => "SELECT COUNT(*) FROM $TableName",
        );
        while ( my @Row = $DBObject->FetchrowArray() ) {
            $TablesData{$TableName}->{Count} = $Row[0] || 0;
        }
    }

    if ( $Test eq 'Is' ) {

        $Self->Is(
            $TablesData{article}->{Count},
            $TablesData{article_data_mime}->{Count},
            'The same amount of rows should be present in article and article_data_mime tables.'
        );
        $Self->Is(
            $TablesData{article}->{MaxID},
            $TablesData{article_data_mime}->{MaxID},
            'The last included ID on each table (article and article_data_mime) should be the same.'
        );

        # TODO:OCBI: Insert a new record, ID should be the next after MAXID
        # Currently is not possible due data migration is already done, including
        # new article data structure
    }
    else {
        $Self->IsNot(
            $TablesData{article}->{Count},
            $TablesData{article_data_mime}->{Count},
            'In article and article_data_mime should not be the same amount of data.'
        );
        $Self->IsNot(
            $TablesData{article}->{MaxID},
            $TablesData{article_data_mime}->{MaxID},
            'The last included ID on each table (article and article_data_mime) should not be the same.'
        );
        $Self->Is(
            $TablesData{article}->{MaxID},
            0,
            'The article table should be empty - MaxID'
        );
        $Self->Is(
            $TablesData{article}->{Count},
            0,
            'The article table should be empty - Count'
        );

    }

};

$CheckData->(
    Test => 'IsNot',
);

my $DBUpdateObject = $Kernel::OM->Create('scripts::DBUpdateTo6::OCBIMigrateArticleData');
$Self->True(
    $DBUpdateObject,
    'Database update object successfully created!'
);

my $RunSuccess = $DBUpdateObject->Run();

$Self->Is(
    1,
    $RunSuccess,
    'DBUpdateObject ran without problems.'
);

$CheckData->(
    Test => 'Is',
);

# Cleanup is done by TmpDatabaseCleanup().

1;
