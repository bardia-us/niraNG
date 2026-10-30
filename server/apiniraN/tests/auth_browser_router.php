<?php
// Test-owned loopback server only. Neither app trusts this variable or forwarded headers in production.
$_SERVER['HTTPS']='on';
$uri=parse_url($_SERVER['REQUEST_URI'],PHP_URL_PATH)??'/';
$root=str_starts_with($uri,'/apiniraN/')?dirname(__DIR__,2):getenv('NIRA_TEST_MYSUB_ROOT');
if (!is_string($root) || $root==='') {http_response_code(500);return true;}
$root=realpath($root);$file=realpath($root.$uri);
if ($file===false || !str_starts_with($file,$root.DIRECTORY_SEPARATOR) || !is_file($file)) {http_response_code(404);return true;}
if (pathinfo($file,PATHINFO_EXTENSION)==='php') {require $file;return true;}
$type=['css'=>'text/css','js'=>'text/javascript'][pathinfo($file,PATHINFO_EXTENSION)]??'application/octet-stream';
header('Content-Type: '.$type);readfile($file);return true;
