//nolint
package traefik_plugin_rewrite_headers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestServeHTTPRequestResponse(t *testing.T) {
	tests := []struct {
		desc      string
		responses struct {
			rewrite       []Rewrite
			reqHeader     http.Header
			expRespHeader http.Header
		}
		requests struct {
			rewrite       []Rewrite
			reqHeader     http.Header
			expRespHeader http.Header
		}
	}{
		{
			desc: "should replace foo by bar in location request and response header",
			responses: struct {
				rewrite       []Rewrite
				reqHeader     http.Header
				expRespHeader http.Header
			}{
				[]Rewrite{
					{
						Header:      "Location",
						Regex:       "foo",
						Replacement: "bar",
					},
				},
				map[string][]string{
					"Location": {"foo", "anotherfoo"},
				},
				map[string][]string{
					"Location": {"bar", "anotherbar"},
				},
			},
			requests: struct {
				rewrite       []Rewrite
				reqHeader     http.Header
				expRespHeader http.Header
			}{[]Rewrite{
				{
					Header:      "Location",
					Regex:       "^http://(.+)$",
					Replacement: "https://$1",
				},
			},
				map[string][]string{
					"Location": {"http://test:1000"},
				},
				map[string][]string{
					"Location": {"https://test:1000"},
				},
			},
		},
		{
			desc: "should replace http by https in location response header",
			responses: struct {
				rewrite       []Rewrite
				reqHeader     http.Header
				expRespHeader http.Header
			}{[]Rewrite{
				{
					Header:      "Location",
					Regex:       "^http://(.+)$",
					Replacement: "https://$1",
				},
			},
				map[string][]string{
					"Location": {"http://test:1000"},
				},
				map[string][]string{
					"Location": {"https://test:1000"},
				},
			},
		},
		{
			desc: "should replace http by https in location response header",
			responses: struct {
				rewrite       []Rewrite
				reqHeader     http.Header
				expRespHeader http.Header
			}{[]Rewrite{
				{
					Header:      "Location",
					Regex:       "^http://(.+)$",
					Replacement: "https://$1",
				},
			},
				map[string][]string{
					"Location": {"http://test:1000"},
				},
				map[string][]string{
					"Location": {"https://test:1000"},
				},
			},
		},
		{
			desc: "should replace http by https in location response header",
			requests: struct {
				rewrite       []Rewrite
				reqHeader     http.Header
				expRespHeader http.Header
			}{[]Rewrite{
				{
					Header:      "Location",
					Regex:       "^http://(.+)$",
					Replacement: "https://$1",
				},
			},
				map[string][]string{
					"Location": {"http://test:1000"},
				},
				map[string][]string{
					"Location": {"https://test:1000"},
				},
			},
		},
		{
			desc: "should reorder Content-Type header in request header",
			requests: struct {
				rewrite       []Rewrite
				reqHeader     http.Header
				expRespHeader http.Header
			}{[]Rewrite{
				{
					Header:      "Content-Type",
					Regex:       `(.*)(charset=.+){1};\s(boundary=.+\"){1}(.*)`,
					Replacement: "$1$3; $2 $4",
				},
			},
				map[string][]string{
					"Content-Type": {`multipart/form-data; charset=utf-8; boundary="__boundary__"`},
				},
				map[string][]string{
					"Content-Type": {`multipart/form-data; boundary="__boundary__"; charset=utf-8`},
				},
			},
		},
		{
			desc: "should turn a Token Authorization request header into Basic",
			requests: struct {
				rewrite       []Rewrite
				reqHeader     http.Header
				expRespHeader http.Header
			}{[]Rewrite{
				{
					Header:      "Authorization",
					Regex:       "^Token (.+)$",
					Replacement: "Basic $1",
				},
			},
				map[string][]string{
					"Authorization": {"Token YWRtaW46c2VjcmV0"},
				},
				map[string][]string{
					"Authorization": {"Basic YWRtaW46c2VjcmV0"},
				},
			},
		},
	}

	for _, test := range tests {
		t.Run(test.desc, func(t *testing.T) {
			config := &Config{
				Rewrites: Rewrites{
					Request:  test.requests.rewrite,
					Response: test.responses.rewrite,
				},
			}

			// Response setup if any
			next := func(rw http.ResponseWriter, req *http.Request) {
				for k, v := range test.responses.reqHeader {
					for _, h := range v {
						rw.Header().Add(k, h)
					}
				}
				rw.WriteHeader(http.StatusOK)
			}

			rewriteBody, err := New(context.Background(), http.HandlerFunc(next), config, "rewriteHeader")
			if err != nil {
				t.Fatal(err)
			}

			recorder := httptest.NewRecorder()
			req := httptest.NewRequest(http.MethodGet, "/", nil)

			// Request setup if any
			for k, v := range test.requests.reqHeader {
				for _, h := range v {
					req.Header.Add(k, h)
				}
			}

			rewriteBody.ServeHTTP(recorder, req)

			// Validate response headers
			for k, expected := range test.responses.expRespHeader {
				values := recorder.Header().Values(k)
				if !testEq(values, expected) {
					t.Errorf("Slice arent equals: expect: %+v, result: %+v", expected, values)
				}
			}

			// Validate request headers
			for k, expected := range test.requests.expRespHeader {
				values := req.Header.Values(k)

				if !testEq(values, expected) {
					t.Errorf("Slice arent equals: expect: %+v, result: %+v", expected, values)
				}
			}
		})
	}
}

func TestServeHTTPHost(t *testing.T) {
	config := &Config{
		Rewrites: Rewrites{
			Request: []Rewrite{
				{
					Header:      "Host",
					Regex:       "^internal\\.(.+)$",
					Replacement: "$1",
				},
			},
		},
	}

	var gotHost, gotHeader string
	next := func(rw http.ResponseWriter, req *http.Request) {
		gotHost = req.Host
		gotHeader = req.Header.Get("Host")
	}

	rewriteBody, err := New(context.Background(), http.HandlerFunc(next), config, "rewriteHeader")
	if err != nil {
		t.Fatal(err)
	}

	req := httptest.NewRequest(http.MethodGet, "http://internal.example.com/", nil)

	rewriteBody.ServeHTTP(httptest.NewRecorder(), req)

	if gotHost != "example.com" {
		t.Errorf("req.Host: expect: example.com, result: %s", gotHost)
	}
	if gotHeader != "" {
		t.Errorf("Host header: expect none, result: %s", gotHeader)
	}
}

func TestServeHTTPUnwrappedWithoutResponseRewrites(t *testing.T) {
	config := &Config{
		Rewrites: Rewrites{
			Request: []Rewrite{{Header: "Authorization", Regex: "^Token (.+)$", Replacement: "Basic $1"}},
		},
	}

	recorder := httptest.NewRecorder()
	var got http.ResponseWriter
	next := func(rw http.ResponseWriter, req *http.Request) {
		got = rw
	}

	rewriteBody, err := New(context.Background(), http.HandlerFunc(next), config, "rewriteHeader")
	if err != nil {
		t.Fatal(err)
	}

	rewriteBody.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/", nil))

	if got != http.ResponseWriter(recorder) {
		t.Errorf("next got %T, expect the original writer", got)
	}
}

// statusRecorder records the Link values sent with each WriteHeader call.
type statusRecorder struct {
	*httptest.ResponseRecorder
	sent [][]string
}

func (s *statusRecorder) WriteHeader(code int) {
	s.sent = append(s.sent, s.Header().Values("Link"))
	if code >= http.StatusOK {
		s.ResponseRecorder.WriteHeader(code)
	}
}

func TestServeHTTPResponseRewrittenOnce(t *testing.T) {
	config := &Config{
		Rewrites: Rewrites{
			Response: []Rewrite{{Header: "Link", Regex: "^(.*)$", Replacement: "x$1"}},
		},
	}

	next := func(rw http.ResponseWriter, req *http.Request) {
		rw.Header().Set("Link", "a")
		rw.WriteHeader(http.StatusEarlyHints)
		rw.Write([]byte("body"))
	}

	rewriteBody, err := New(context.Background(), http.HandlerFunc(next), config, "rewriteHeader")
	if err != nil {
		t.Fatal(err)
	}

	recorder := &statusRecorder{ResponseRecorder: httptest.NewRecorder()}
	rewriteBody.ServeHTTP(recorder, httptest.NewRequest(http.MethodGet, "/", nil))

	if len(recorder.sent) != 2 || !testEq(recorder.sent[0], []string{"a"}) || !testEq(recorder.sent[1], []string{"xa"}) {
		t.Errorf("Link per response: expect [[a] [xa]], result: %v", recorder.sent)
	}
}

func testEq(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
