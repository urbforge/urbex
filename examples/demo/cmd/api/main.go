// api answers the web page with a tip about Urbex, the environment it
// runs in and its version.
package main

import (
	"encoding/json"
	"log"
	"math/rand/v2"
	"net/http"
	"os"
)

const version = "1.0.0"

var tips = []string{
	"Every push to main is deployed to staging.",
	"A release is a tag: urbex release, then urbex promote.",
	"Each service runs in its own LXC, per environment.",
	"Logs and metrics are in Grafana, with nothing to set up.",
	"An application that uses a database gets its own role and schema.",
}

func main() {
	http.HandleFunc("/tip", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"tip":     tips[rand.IntN(len(tips))],
			"env":     os.Getenv("DEMO_ENV"),
			"version": version,
		})
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("ok")) })
	log.Printf("demo api %s listening on :%s", version, os.Getenv("PORT"))
	log.Fatal(http.ListenAndServe(":"+os.Getenv("PORT"), nil))
}
