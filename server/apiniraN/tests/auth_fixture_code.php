<?php
// Fixture helper: never invokes an app storage adapter or reads deployed data.
require_once dirname(__DIR__).'/admin-auth/vendor/autoload.php';
$secret=$argv[1]??''; if (preg_match('/\A[A-Z2-7]{16,128}\z/',$secret)!==1) exit(2);
echo OTPHP\TOTP::create($secret)->at((int)($argv[2]??time()));
