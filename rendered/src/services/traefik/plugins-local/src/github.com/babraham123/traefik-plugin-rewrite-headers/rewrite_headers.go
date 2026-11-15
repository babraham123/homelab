//nolint
package traefik_plugin_rewrite_headers

import (
	"bufio"
	"context"
	"fmt"
	"net"
	"net/http"
	"regexp"
	"strings"
)

// Rewrite holds one rewrite body configuration.
type Rewrite struct {
	Header      string `json:"header,omitempty"`
	Regex       string `json:"regex,omitempty"`
	Replacement string `json:"replacement,omitempty"`
}

// Config holds the plugin configuration.
type Config struct {
	Rewrites Rewrites `json:"rewrites,omitempty"`
}

type Rewrites struct {
	Request  []Rewrite `json:"request,omitempty"`
	Response []Rewrite `json:"response,omitempty"`
}

// CreateConfig creates and initializes the plugin configuration.
func CreateConfig() *Config {
	return &Config{}
}

type rewrite struct {
	header      string
	regex       *regexp.Regexp
	replacement string
}

type rewriteBody struct {
	name      string
	next      http.Handler
	responses []rewrite
	requests  []rewrite
}

// New creates and returns a new rewrite body plugin instance.
func New(_ context.Context, next http.Handler, config *Config, name string) (http.Handler, error) {
	responses := make([]rewrite, len(config.Rewrites.Response))
	requests := make([]rewrite, len(config.Rewrites.Request))

	for i, rewriteConfig := range config.Rewrites.Response {
		regex, err := regexp.Compile(rewriteConfig.Regex)
		if err != nil {
			return nil, fmt.Errorf("error compiling regex %q: %w", rewriteConfig.Regex, err)
		}

		responses[i] = rewrite{
			header:      rewriteConfig.Header,
			regex:       regex,
			replacement: rewriteConfig.Replacement,
		}
	}

	for i, rewriteConfig := range config.Rewrites.Request {
		regex, err := regexp.Compile(rewriteConfig.Regex)
		if err != nil {
			return nil, fmt.Errorf("error compiling regex %q: %w", rewriteConfig.Regex, err)
		}

		requests[i] = rewrite{
			header:      rewriteConfig.Header,
			regex:       regex,
			replacement: rewriteConfig.Replacement,
		}
	}

	return &rewriteBody{
		name:      name,
		next:      next,
		responses: responses,
		requests:  requests,
	}, nil
}

func (r *rewriteBody) ServeHTTP(rw http.ResponseWriter, req *http.Request) {
	for _, rewrite := range r.requests {
		// net/http moves the Host header into req.Host and leaves it out of req.Header
		if strings.EqualFold(rewrite.header, "Host") {
			if req.Host != "" {
				req.Host = strings.TrimSpace(rewrite.regex.ReplaceAllString(req.Host, rewrite.replacement))
			}
			continue
		}

		headers := req.Header.Values(rewrite.header)

		if len(headers) == 0 {
			continue
		}

		req.Header.Del(rewrite.header)

		for _, header := range headers {
			value := rewrite.regex.ReplaceAllString(header, rewrite.replacement)
			req.Header.Add(rewrite.header, strings.TrimSpace(value))
		}
	}

	// Under Yaegi, http.ResponseController can't see a wrapper's Unwrap or Flush, so a
	// wrapped writer can't stream; only Hijack (WebSockets) passes through. Wrap only when
	// there are response headers to rewrite.
	if len(r.responses) == 0 {
		r.next.ServeHTTP(rw, req)
		return
	}

	r.next.ServeHTTP(&responseWriter{writer: rw, rewrites: r.responses}, req)
}

type responseWriter struct {
	writer      http.ResponseWriter
	rewrites    []rewrite
	wroteHeader bool
}

func (r *responseWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	hijacker, ok := r.writer.(http.Hijacker)
	if !ok {
		return nil, nil, fmt.Errorf("%T doesn't support hijacking", r.writer)
	}
	return hijacker.Hijack()
}

func (r *responseWriter) Header() http.Header {
	return r.writer.Header()
}

func (r *responseWriter) Write(bytes []byte) (int, error) {
	if !r.wroteHeader {
		r.WriteHeader(http.StatusOK)
	}
	return r.writer.Write(bytes)
}

func (r *responseWriter) WriteHeader(statusCode int) {
	// An informational response (103 Early Hints) shares the header map with the final one,
	// which would get the rewrites a second time
	if statusCode < http.StatusOK {
		r.writer.WriteHeader(statusCode)
		return
	}
	if r.wroteHeader {
		return
	}
	r.wroteHeader = true

	for _, rewrite := range r.rewrites {
		headers := r.writer.Header().Values(rewrite.header)

		if len(headers) == 0 {
			continue
		}

		r.writer.Header().Del(rewrite.header)

		for _, header := range headers {
			value := rewrite.regex.ReplaceAllString(header, rewrite.replacement)
			r.writer.Header().Add(rewrite.header, value)
		}
	}

	r.writer.WriteHeader(statusCode)
}
