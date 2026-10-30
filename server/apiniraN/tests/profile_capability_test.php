<?php
declare(strict_types=1);
require_once dirname(__DIR__).'/registry.php';
$cases = [
    ['android', ['profile_format_version'=>1], ['X-Nira-Profile-Version: 1']],
    ['android', [], []],
    ['android', ['profile_format_version'=>'1'], []],
    ['android', ['profile_format_version'=>2], []],
    ['windows', ['profile_format_version'=>1], []],
    ['unknown', ['profile_format_version'=>1], []],
];
foreach ($cases as [$platform,$payload,$expected]) {
    if (registry_profile_capability_headers($platform,$payload)!==$expected) throw new RuntimeException('Profile capability forwarding mismatch');
}
echo "Profile capability: 6 checks passed\n";
$headerCases=[
    ['android',['HTTP_X_NIRA_PROFILE_VERSION'=>'1'],['X-Nira-Profile-Version: 1']],
    ['android',[],[]],
    ['android',['HTTP_X_NIRA_PROFILE_VERSION'=>1],[]],
    ['android',['HTTP_X_NIRA_PROFILE_VERSION'=>'01'],[]],
    ['android',['HTTP_X_NIRA_PROFILE_VERSION'=>'1 '],[]],
    ['android',['HTTP_X_NIRA_PROFILE_VERSION'=>'1, 1'],[]],
    ['android',['HTTP_X_NIRA_PROFILE_VERSION'=>['1']],[]],
    ['windows',['HTTP_X_NIRA_PROFILE_VERSION'=>'1'],[]],
    ['unknown',['HTTP_X_NIRA_PROFILE_VERSION'=>'1'],[]],
];
foreach($headerCases as [$platform,$server,$expected]) if (registry_profile_capability_request_headers($platform,$server)!==$expected) throw new RuntimeException('Strict request header capability mismatch');
echo "Profile request header: 9 checks passed\n";
