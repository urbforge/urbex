// web is the demo's page: it asks api for a tip, at the address Urbex
// gives it (API_URL, since urbex.yaml says web uses api), and shows it:
// as a page in a browser, as a line of text to curl.
package main

import (
	"encoding/json"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

var page = template.Must(template.New("page").Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Urbex demo</title>
<style>
  body { margin: 0; min-height: 100vh; display: grid; place-items: center;
         font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0; }
  main { max-width: 32rem; padding: 2rem; }
  h1 { font-size: 2.5rem; margin: 0 0 .5rem; }
  .card { background: #1e293b; border-radius: 1rem; padding: 1.5rem; margin-top: 1.5rem; }
  .tip { font-size: 1.25rem; }
  .meta { color: #94a3b8; font-size: .9rem; margin-top: 1rem; }
  .env { display: inline-block; padding: .1rem .6rem; border-radius: 1rem; background: #22c55e; color: #052e16; }
</style>
</head>
<body>
<main>
  <h1>Urbex demo</h1>
  <p>A web page and the API it calls, deployed by Urbex.</p>
  <div class="card">
    {{if .Err}}<p class="tip">The API didn't answer: {{.Err}}</p>
    {{else}}<p class="tip">{{.Tip}}</p>
    <p class="meta"><span class="env">{{.Env}}</span></p>{{end}}
  </div>
</main>
</body>
</html>
`))

type tip struct {
	Tip, Env string
	Err      string
}

func main() {
	api := os.Getenv("API_URL")
	client := &http.Client{Timeout: 3 * time.Second}
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		var t tip
		resp, err := client.Get(api + "/tip")
		if err == nil {
			err = json.NewDecoder(resp.Body).Decode(&t)
			resp.Body.Close()
		}
		if err != nil {
			t.Err = err.Error()
		}
		if !strings.Contains(r.Header.Get("Accept"), "text/html") {
			// curl: the page as text.
			if t.Err != "" {
				fmt.Fprintf(w, "Urbex demo: the API didn't answer: %s\n", t.Err)
				return
			}
			fmt.Fprintf(w, "Urbex demo (%s)\n  %s\n", t.Env, t.Tip)
			return
		}
		page.Execute(w, t)
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("ok")) })
	log.Printf("demo web listening on :%s, api at %s", os.Getenv("PORT"), api)
	log.Fatal(http.ListenAndServe(":"+os.Getenv("PORT"), nil))
}
