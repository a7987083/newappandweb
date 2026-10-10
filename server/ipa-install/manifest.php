<?php
// PHP 7.0 compatible. Deploy as https://app3.zonoeios.xyz/ipa-install/manifest.php
// Generates XML only: no file upload or IPA storage.
header('Content-Type: application/xml; charset=UTF-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
function bad($message) { http_response_code(400); header('Content-Type: text/plain; charset=UTF-8'); exit($message); }
$ipa = isset($_GET['fetchurl']) ? trim($_GET['fetchurl']) : '';
$id = isset($_GET['bundleid']) ? trim($_GET['bundleid']) : '';
$name = isset($_GET['name']) ? trim($_GET['name']) : '';
$version = isset($_GET['version']) ? trim($_GET['version']) : '';
if (strlen($ipa) > 2048 || strlen($id) > 255 || strlen($name) > 255 || strlen($version) > 64) bad('invalid size');
$parts = parse_url($ipa);
if (!is_array($parts) || empty($parts['scheme']) || empty($parts['host'])) bad('missing URL');
if (!in_array(strtolower($parts['scheme']), array('http', 'https'), true)) bad('invalid URL scheme');
if (!preg_match('/^[A-Za-z0-9.-]+$/D', $id) || !$id) bad('invalid bundle id');
if (!$version || !$name) bad('missing metadata');
// NOTE: URLs referencing loopback are only meaningful to the iOS device installing its own IPA.
// This endpoint never fetches the URL, avoiding SSRF and uploads.
function xml($s) { return htmlspecialchars($s, ENT_XML1 | ENT_QUOTES, 'UTF-8'); }
echo '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' . "\n";
echo '<plist version="1.0"><dict><key>items</key><array><dict><key>assets</key><array><dict>';
echo '<key>kind</key><string>software-package</string><key>url</key><string>' . xml($ipa) . '</string>';
echo '</dict></array><key>metadata</key><dict><key>bundle-identifier</key><string>' . xml($id) . '</string>';
echo '<key>bundle-version</key><string>' . xml($version) . '</string>';
echo '<key>kind</key><string>software</string><key>title</key><string>' . xml($name) . '</string>';
echo '</dict></dict></array></dict></plist>';
