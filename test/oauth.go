// Ref:
// https://www.benburwell.com/posts/intercepting-golang-tls-with-wireshark/
// https://github.com/TwiN/gatus/pull/259/files
package main

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/clientcredentials"
)

const (
	sslKeyLogFile = "./ssl_key.log"
	tokenURL      = "https://auth.{{ site.url }}/api/oidc/token"
	testURL       = "https://vmalert.{{ site.url }}"

	dnsResolverIP        = "1.1.1.1:53"
	dnsResolverProto     = "udp"
	dnsResolverTimeoutMs = 5000
)

var scopes = []string{"authelia.bearer.authz"}

func main() {
	clientID := os.Getenv("CLIENT_ID")
	clientSecret := os.Getenv("CLIENT_SECRET")

	f, err := os.OpenFile(sslKeyLogFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		panic(err)
	}
	defer f.Close()

	dialer := &net.Dialer{
		Resolver: &net.Resolver{
			PreferGo: true,
			Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
				d := net.Dialer{
					Timeout: time.Duration(dnsResolverTimeoutMs) * time.Millisecond,
				}
				return d.DialContext(ctx, dnsResolverProto, dnsResolverIP)
			},
		},
	}

	dialContext := func(ctx context.Context, network, addr string) (net.Conn, error) {
		return dialer.DialContext(ctx, network, addr)
	}

	httpClient := &http.Client{
		Transport: &http.Transport{
			DialContext: dialContext,
			TLSClientConfig: &tls.Config{
				KeyLogWriter: f,
			},
		},
	}

	oauth2cfg := clientcredentials.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		Scopes:       scopes,
		TokenURL:     tokenURL,
	}
	ctx := context.WithValue(context.Background(), oauth2.HTTPClient, httpClient)
	oauthClient := oauth2cfg.Client(ctx)

	resp, err := oauthClient.Get(testURL)
	if err != nil {
		panic(err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		panic(err)
	}
	fmt.Print(string(body))
}
