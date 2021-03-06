/* SET THE HOST AND PORT OF WORDPRESS
 * *********************************************************/
vcl 4.0;
import std;

backend default {
  .host = "127.0.0.1";
  .port = "8080";
  .first_byte_timeout = 60s;
  .connect_timeout = 300s;
}
 
# SET THE ALLOWED IP OF PURGE REQUESTS
# ##########################################################
acl purge {
  "localhost";
  "127.0.0.1";
}

acl Blacklist {

}

acl Whitelist {
 
}

#THE RECV FUNCTION
# ##########################################################
sub vcl_recv {

# set realIP by trimming CloudFlare IP which will be used for various checks
set req.http.X-Actual-IP = regsub(req.http.X-Forwarded-For, "[, ].*$", ""); 

        # FORWARD THE IP OF THE REQUEST
  if (req.restarts == 0) {
    if (req.http.x-forwarded-for) {
      set req.http.X-Forwarded-For =
      req.http.X-Forwarded-For + ", " + client.ip;
    } else {
      set req.http.X-Forwarded-For = client.ip;
    }
  }
  
  #Disable "xmlrpc.php" request
    if ((req.url ~ "^/xmlrpc\.php" && !(client.ip ~ Whitelist)) || (client.ip ~ Blacklist)) {
        return(synth(750, "Moved Temporarily"));
    }


 # Purge request check sections for hash_always_miss, purge and ban
 # BLOCK IF NOT IP is not in purge acl
 # ##########################################################

  # Enable smart refreshing using hash_always_miss
if (req.http.Cache-Control ~ "no-cache") {
    if (client.ip ~ purge || !std.ip(req.http.X-Actual-IP, "1.2.3.4") ~ purge) {
         set req.hash_always_miss = true;
    }
}

if (req.method == "PURGE") {
    if (!client.ip ~ purge || !std.ip(req.http.X-Actual-IP, "1.2.3.4") ~ purge) {
        return(synth(405,"Not allowed."));
        }
		# ban("req.http.host == " + req.http.host + " && req.url ~ " + req.url);
        # return(synth(200,"host:" + req.http.host + " url:" + req.url + " Ban added"));
		
    return (purge);
  }

if (req.method == "BAN") {
        # Same ACL check as above:
        if (!client.ip ~ purge || !std.ip(req.http.X-Actual-IP, "1.2.3.4") ~ purge) {
                        return(synth(403, "Not allowed."));
        }
        ban("req.http.host == " + req.http.host +
                  " && req.url == " + req.url);

        # Throw a synthetic page so the
        # request won't go to the backend.
        return(synth(200, "Ban added"));
}

# clear cache for post update-delete
if( req.url ~ "^/clearcache" ) {
	if( req.url ~ "uri=" ) {
	 ban( "req.url ~ ^/" + regsub( req.url, ".*uri=", "") );
	 ban( "req.http.host == "+req.http.host+" && req.url ~ ^/$");
	 ban( "req.http.host == "+req.http.host+" && req.url ~ ^/category");
	}    # for example /clearcache?uri=foo/bar

	if( req.url ~ "singlefile=" ) {
	 ban( "req.url ~ ^/" + regsub( req.url, ".*singlefile=", "") );
	}

	 return(synth(200, "Ban added"));    
  }

# Unset cloudflare cookies
# Remove has_js and CloudFlare/Google Analytics __* cookies.
      set req.http.Cookie = regsuball(req.http.Cookie, "(^|;\s*)(_[_a-z]+|has_js)=[^;]*", "");
      # Remove a ";" prefix, if present.
     set req.http.Cookie = regsub(req.http.Cookie, "^;\s*", "");

  # For Testing: If you want to test with Varnish passing (not caching) uncomment
  # return( pass );

  # FORWARD THE IP OF THE REQUEST
  if (req.restarts == 0) {
    if (req.http.x-forwarded-for) {
      set req.http.X-Forwarded-For =
      req.http.X-Forwarded-For + ", " + client.ip;
    } else {
      set req.http.X-Forwarded-For = client.ip;
    }
  }

# DO NOT CACHE RSS FEED
 if (req.url ~ "/feed(/)?") {
	return ( pass ); 
}

## Do not cache search results, comment these 3 lines if you do want to cache them

if (req.url ~ "/\?s\=") {
	return ( pass ); 
}

# CLEAN UP THE ENCODING HEADER.
  # SET TO GZIP, DEFLATE, OR REMOVE ENTIRELY.  WITH VARY ACCEPT-ENCODING
  # VARNISH WILL CREATE SEPARATE CACHES FOR EACH
  # DO NOT ACCEPT-ENCODING IMAGES, ZIPPED FILES, AUDIO, ETC.
  # ##########################################################
  if (req.http.Accept-Encoding) {
    if (req.url ~ "\.(jpg|png|gif|gz|tgz|bz2|tbz|mp3|ogg)$") {
      # No point in compressing these
      unset req.http.Accept-Encoding;
    } elsif (req.http.Accept-Encoding ~ "gzip") {
      set req.http.Accept-Encoding = "gzip";
    } elsif (req.http.Accept-Encoding ~ "deflate") {
      set req.http.Accept-Encoding = "deflate";
    } else {
      # unknown algorithm
      unset req.http.Accept-Encoding;
    }
  }

  # PIPE ALL NON-STANDARD REQUESTS
  # ##########################################################
  if (req.method != "GET" &&
    req.method != "HEAD" &&
    req.method != "PUT" && 
    req.method != "POST" &&
    req.method != "TRACE" &&
    req.method != "OPTIONS" &&
    req.method != "DELETE") {
      return (pipe);
  }
   
  # ONLY CACHE GET AND HEAD REQUESTS
  # ##########################################################
  if (req.method != "GET" && req.method != "HEAD") {
    return (pass);
  }
  
  # OPTIONAL: DO NOT CACHE LOGGED IN USERS (THIS OCCURS IN FETCH TOO, EITHER
  # COMMENT OR UNCOMMENT BOTH
  # ##########################################################
  if ( req.http.cookie ~ "wordpress_logged_in" ) {
    return( pass );
  }
  
  # IF THE REQUEST IS NOT FOR A PREVIEW, WP-ADMIN OR WP-LOGIN
  # THEN UNSET THE COOKIES
  # ##########################################################
  if (!(req.url ~ "wp-(login|admin)") 
    && !(req.url ~ "&preview=true" ) 
  ){
    unset req.http.cookie;
  }

  # IF BASIC AUTH IS ON THEN DO NOT CACHE
  # ##########################################################
  if (req.http.Authorization || req.http.Cookie) {
    return (pass);
  }
  
  # IF YOU GET HERE THEN THIS REQUEST SHOULD BE CACHED
  # ##########################################################
  return (hash);
  # This is for phpmyadmin
 if (req.http.Host == "pmadomain.com") {
  return (pass);
 }
}

# HIT FUNCTION
# ##########################################################
sub vcl_hit {
  # IF THIS IS A PURGE REQUEST THEN DO THE PURGE
  # ##########################################################
  if (req.method == "PURGE") {
    #
    # This is now handled in vcl_recv.
    #
    # purge;
    return (synth(200, "Purged."));
  }
  return (deliver);
}

# MISS FUNCTION
# ##########################################################
sub vcl_miss {
  if (req.method == "PURGE") {
    #
    # This is now handled in vcl_recv.
    #
    # purge;
    return (synth(200, "Purged."));
  }
  return (fetch);
}

# FETCH FUNCTION
# ##########################################################
sub vcl_backend_response {
  # I SET THE VARY TO ACCEPT-ENCODING, THIS OVERRIDES W3TC 
  # TENDANCY TO SET VARY USER-AGENT.  YOU MAY OR MAY NOT WANT
  # TO DO THIS
  # ##########################################################
  set beresp.http.Vary = "Accept-Encoding";

  # IF NOT WP-ADMIN THEN UNSET COOKIES AND SET THE AMOUNT OF 
  # TIME THIS PAGE WILL STAY CACHED (TTL)
  # ##########################################################
  if (!(bereq.url ~ "wp-(login|admin)") && !bereq.http.cookie ~ "wordpress_logged_in" ) {
    unset beresp.http.set-cookie;
    set beresp.ttl = 52w;
#    set beresp.grace =1w;
  }

  if (beresp.ttl <= 0s ||
    beresp.http.Set-Cookie ||
    beresp.http.Vary == "*") {
      set beresp.ttl = 120 s;
      # set beresp.ttl = 120s;
      set beresp.uncacheable = true;
      return (deliver);
  }

  return (deliver);
}
sub vcl_synth {
 if (resp.status == 503) {
		# set obj.http.location = req.http.Location;
		set resp.status = 404;
        set resp.reason = "Not Found";
        return (deliver);
    }
	
    if (resp.status == 750) {
        set resp.status = 302;
        set resp.http.Location = "http://127.0.0.1";
        return(deliver);
    }
}
# DELIVER FUNCTION
# ##########################################################
sub vcl_deliver {
  # IF THIS PAGE IS ALREADY CACHED THEN RETURN A 'HIT' TEXT 
  # IN THE HEADER (GREAT FOR DEBUGGING)
  # ##########################################################
  if (obj.hits > 0) {
    set resp.http.X-Cache = "HIT";
  # IF THIS IS A MISS RETURN THAT IN THE HEADER
  # ##########################################################
  } else {
    set resp.http.X-Cache = "MISS";
  }
}
