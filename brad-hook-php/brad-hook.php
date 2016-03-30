<?php

function ip_in_range( $ip, $range ) {
  if ( strpos( $range, '/' ) == false ) {
    $range .= '/32';
  }
  // $range is in IP/CIDR format eg 127.0.0.1/24
  list( $range, $netmask ) = explode( '/', $range, 2 );
  $range_decimal = ip2long( $range );
  $ip_decimal = ip2long( $ip );
  $wildcard_decimal = pow( 2, ( 32 - $netmask ) ) - 1;
  $netmask_decimal = ~ $wildcard_decimal;
  return ( ( $ip_decimal & $netmask_decimal ) == ( $range_decimal & $netmask_decimal ) );
}

function get_client_ip_server() {
    $ipaddress = '';
    if ($_SERVER['HTTP_CLIENT_IP'])
        $ipaddress = $_SERVER['HTTP_CLIENT_IP'];
    else if($_SERVER['HTTP_X_FORWARDED_FOR'])
        $ipaddress = $_SERVER['HTTP_X_FORWARDED_FOR'];
    else if($_SERVER['HTTP_X_FORWARDED'])
        $ipaddress = $_SERVER['HTTP_X_FORWARDED'];
    else if($_SERVER['HTTP_FORWARDED_FOR'])
        $ipaddress = $_SERVER['HTTP_FORWARDED_FOR'];
    else if($_SERVER['HTTP_FORWARDED'])
        $ipaddress = $_SERVER['HTTP_FORWARDED'];
    else if($_SERVER['REMOTE_ADDR'])
        $ipaddress = $_SERVER['REMOTE_ADDR'];
    else
        $ipaddress = 'UNKNOWN';
 
    return $ipaddress;
}

$ip = get_client_ip_server();
error_log("Calling from ". $ip);


$name = $_GET['name'];
$env = $_GET['env'];

error_log("Requested deployment for " . $name . " " . $env . "...");

// Check projects
$regexp = "/projects\\[\\\"(?<p>[a-zA-Z\\_]*)\\\"\\](?:.*)/i";
preg_match_all($regexp, file_get_contents("../brad.conf"), $keys, PREG_PATTERN_ORDER);
$projects = $keys["p"];

if ($ip == "::1" || $ip == "127.0.0.1"
    || 
    // Bitbucket
    ip_in_range($ip, "131.103.20.160/27") || ip_in_range($ip, "165.254.145.0/26") || ip_in_range($ip, "104.192.143.0/24")
    ||
    // Github
    ip_in_range($ip, "92.30.252.0/22")) {


    if (($env == "prod" || $env == "beta") && in_array($name, $projects)) {
    
      error_log("Deploying for " . $name . " " . $env);
      $output = shell_exec("../brad -y " . $name . " " . $env);
      
      error_log("Done.");
      header("HTTP/1.0 200 OK");
      echo "OK";
      echo $output;
      exit(0);
    
    } else {
      
      error_log("Bad name/env");
      header("HTTP/1.0 404 Not Found");
      echo "Not Found";
      exit(0);

    }

} else {
      
  error_log("IP not in range");
  header("HTTP/1.0 403 Unauthorized");
  echo "Unauthorized";
  exit(0);

}