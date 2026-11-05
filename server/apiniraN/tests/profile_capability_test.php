<?php
declare(strict_types=1);
require_once dirname(__DIR__) . '/registry.php';

$cases = [];
foreach (['android', 'windows'] as $platform) {
    foreach ([
        [['profile_format_version' => 1], ['X-Nira-Profile-Version: 1']],
        [[], []],
        [['profile_format_version' => '1'], []],
        [['profile_format_version' => 1.0], []],
        [['profile_format_version' => true], []],
        [['profile_format_version' => 2], []],
        [['profile_format_version' => null], []],
    ] as [$payload, $expected]) {
        $cases[] = [$platform, $payload, $expected];
    }
}
foreach (['unknown', '', 'Windows', 'ios'] as $platform) {
    $cases[] = [$platform, ['profile_format_version' => 1], []];
}
foreach ($cases as [$platform, $payload, $expected]) {
    if (registry_profile_capability_headers($platform, $payload) !== $expected) {
        throw new RuntimeException('Profile capability forwarding mismatch: ' . $platform);
    }
}
echo 'Profile capability: ' . count($cases) . " checks passed\n";

$headerCases = [];
foreach (['android', 'windows'] as $platform) {
    foreach ([
        [['HTTP_X_NIRA_PROFILE_VERSION' => '1'], ['X-Nira-Profile-Version: 1']],
        [[], []],
        [['HTTP_X_NIRA_PROFILE_VERSION' => 1], []],
        [['HTTP_X_NIRA_PROFILE_VERSION' => true], []],
        [['HTTP_X_NIRA_PROFILE_VERSION' => '2'], []],
        [['HTTP_X_NIRA_PROFILE_VERSION' => '01'], []],
        [['HTTP_X_NIRA_PROFILE_VERSION' => '1 '], []],
        [['HTTP_X_NIRA_PROFILE_VERSION' => ' 1'], []],
        [['HTTP_X_NIRA_PROFILE_VERSION' => '1, 1'], []],
        [['HTTP_X_NIRA_PROFILE_VERSION' => ['1']], []],
    ] as [$server, $expected]) {
        $headerCases[] = [$platform, $server, $expected];
    }
}
foreach (['unknown', '', 'Windows', 'ios'] as $platform) {
    $headerCases[] = [$platform, ['HTTP_X_NIRA_PROFILE_VERSION' => '1'], []];
}
foreach ($headerCases as [$platform, $server, $expected]) {
    if (registry_profile_capability_request_headers($platform, $server) !== $expected) {
        throw new RuntimeException('Strict request header capability mismatch: ' . $platform);
    }
}
echo 'Profile request header: ' . count($headerCases) . " checks passed\n";