# /etc/nginx/apps.badita.com.d/antonim-headers.inc
# nginx gotcha: a location with ANY add_header drops every add_header inherited
# from the server block (HSTS, Referrer-Policy). Each antonim location that adds
# its own header includes this file to put them back.
add_header Strict-Transport-Security "max-age=31536000" always;
add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
add_header X-Content-Type-Options    "nosniff" always;
