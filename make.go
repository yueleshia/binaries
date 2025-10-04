package main

// @TODO: List repo (scoped to a user) that use this pipeline to coordinate updates

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

var OWNER_REPO = "yueleshia/binaries"
var RELEASE_TAG = "nonsemantic" 
var DIR_BIN = "bin"
var PAT_PATH = "pat/yueleshia_binaries"

var ASSETS []Asset
type Asset struct {
	Key     string `json:"key"`
	Dl_url  string `json:"dl_url"`
	Sha256  string `json:"sha256"`
	id      uint

	action  uint8
	is_local_uptodate bool
	is_cache_uptodate bool
}

const (
	ACT_DOWNLOAD uint8 = iota
	ACT_RECREATE
	ACT_UPLOAD
	ACT_SKIP
	ACT_DELETE
)

//run: go run % apply
func main() {
	start := time.Now()
	defer func() {
		L_INFO.Printf("Time taken: %d ms\n", time.Since(start).Milliseconds())
	}()

	{
		log_level := INFO
		if log_level <= DEBUG { L_DEBUG = log.New(os.Stderr, "", log.Lshortfile) }
		if log_level <= INFO { L_INFO = log.New(os.Stderr, "", 0) }
		if log_level <= ERROR { L_ERROR = log.New(os.Stderr, "", log.Lshortfile) }
	}

	{
		_, this_file_path, _, ok := runtime.Caller(0)
		if !ok {
			L_ERROR.Fatal("Could not get runtime info")
		}
		Must1(os.Chdir(filepath.Dir(this_file_path)))
		fh := Must(os.Open("binaries.json"))
		deserialiser := json.NewDecoder(fh)
		Must1(deserialiser.Decode(&ASSETS))
	}

	if len(os.Args) < 2 {
		fmt.Println(`Usage: go run make.go <subcommand>
Subcommands
  assets
  plan
  apply
`)
		os.Exit(1)
	}

	arg := os.Args[1]
	switch arg {
	case "assets":
		Must1(json.NewEncoder(os.Stdout).Encode(ASSETS))
	case "plan":
		release_id, plan := step_plan()
		if has_changes(plan) {
			step_execute(true, release_id, plan)
		} else {
			L_INFO.Print("No changes")
		}
	case "apply":
		release_id, plan := step_plan()
		if has_changes(plan) {
			step_execute(false, release_id, plan)
		} else {
			L_INFO.Print("No changes")
		}
	default:
		L_INFO.Fatalf("Unknown subcommand %q", arg)
	}
}

var PAT *string = nil

func get_pat() string {
	if PAT == nil {
		cmd := exec.Command("pass", "show", PAT_PATH)
		cmd.Stdin = os.Stdin
		arr := Must(cmd.Output())
		return string(bytes.TrimRight(arr, "\r\n"))
	}
	return *PAT
}

func has_changes(plan map[string]*Asset) bool {
	for _, asset := range plan {
		if asset.action != ACT_SKIP {
			return true
		}
	}
	return false
}

func step_plan() (uint, map[string]*Asset) {
	var input []byte

	cache_chan := make(chan bool, 1)
	cache_info := make(map[string]string, len(ASSETS) + 10) 
	// Perform sha256 for all files, since we assume network will be slower
	go func() {
		for _, asset := range ASSETS {
			path := filepath.Join(DIR_BIN, asset.Key)

			fh, err := os.Open(path)
			if err != nil {
				cache_info[asset.Key] = ""
				if !os.IsNotExist(err) {
					L_ERROR.Printf("Error opening file %q: %v\n", path, err)
				}
				continue
			}

			hash := sha256.New()
			if _, err := io.Copy(hash, fh); err != nil {
			} else {
				sha256 := hash.Sum(nil)
				cache_info[asset.Key] = fmt.Sprintf("%x", sha256)
			}

			if err := fh.Close(); err != nil {
				L_ERROR.Printf("Error closing file %q: %v\n", path, err)
			}
		}
		cache_chan <- true
	}()

	api_url := fmt.Sprintf("/repos/%s/releases/tags/%s", OWNER_REPO, RELEASE_TAG)
	if true {
		L_INFO.Printf("Reading releases: GET %s", api_url)
		req := Must(http.NewRequest("GET", "https://api.github.com" + api_url, nil))
		req.Header.Set("Accept", "application/vnd.github.v3+json")
		req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
		input = Must(handle_request(req))
		if false {
			ioutil.WriteFile("temp.json", input, 0644)
			fmt.Println("DEV: Exiting after writing to temp.json")
			os.Exit(1)
		}
	} else {
		L_INFO.Print("Reading cached release")
		input = Must(ioutil.ReadFile("temp.json"))
	}

	plan := make(map[string]*Asset, len(ASSETS) + 10)
	for _, x := range ASSETS {
		asset := x
		//asset.action = ACT_DOWNLOAD // Does this by default since it is 0 initialized
		plan[x.Key] = &asset
	}

	// Check external repo
	var release_id uint
	{
		type RepoAsset struct {
			Id uint `json:"id"`
			Name string `json:"name"`
			Digest string `json:"digest"`
		}
		type Release struct {
			Id uint `json:"id"`
			Assets []RepoAsset`json:"assets"`
		}
		var release Release
		json.Unmarshal(input, &release)
		release_id = release.Id

		for _, x := range release.Assets {
			name := string(x.Name)
			asset, ok := plan[name]
			if !ok {
				plan[name] = &Asset{ Key: name, action: ACT_DELETE, id: x.Id }
				continue
			} else {
				asset.id = x.Id
			}
			sha256, ok := strings.CutPrefix(x.Digest, "sha256:")
			if !ok {
				L_INFO.Fatalf("Error parsing Gitub api %q\n'digest' field for assets no longer is a sha256\n", api_url)
			}

			if sha256 != asset.Sha256 {
				asset.action = ACT_RECREATE
			} else {
				asset.action = ACT_SKIP
			}
		}
	}

	// Update plan with local cache info
	<-cache_chan
	for key, local_sha256 := range cache_info {
		asset, ok := plan[key]
		if !ok {
			L_ERROR.Fatalf("Key should exist in plan: %q", key)
		}

		if asset.Dl_url == "" && local_sha256 != asset.Sha256 {
			L_STDERR.Fatalf("The SHA256 for %q is out of date.\n  binaries.json: %s\n  expected:      %s", key, asset.Sha256, local_sha256)
		} else if asset.action == ACT_DOWNLOAD && local_sha256 != asset.Sha256 {
			L_DEBUG.Printf("Cached sha256 for %q matches", key, local_sha256)
			asset.action = ACT_UPLOAD
		}
	}
	return release_id, plan
}

func step_execute(is_dry bool, release_id uint, plan map[string]*Asset) {
	for _, asset := range plan {
		path := filepath.Join(DIR_BIN, asset.Key)
		var fh *os.File
		defer func() {
			if fh != nil {
				Must1(fh.Close())
			}
		}()

		switch (asset.action) {
		case ACT_DELETE:
			L_INFO.Printf("Deleting %s", asset.Key)

			if !is_dry {
				// https://docs.github.com/en/rest/releases/assets?apiVersion=2022-11-28#delete-a-release-asset
				endpoint := fmt.Sprintf("/repos/%s/releases/assets/%d", OWNER_REPO, asset.id)
				req := Must(http.NewRequest("DELETE", "https://api.github.com" + endpoint, nil))
				req.Header.Set("Accept", "application/vnd.github.v3+json")
				req.Header.Set("Authorization", "Bearer " + get_pat())
				req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
				_  = Must(handle_request(req))
			}

		case ACT_RECREATE:
			L_INFO.Printf("Deleting existing %s", asset.Key)
			if !is_dry {
				// https://docs.github.com/en/rest/releases/assets?apiVersion=2022-11-28#delete-a-release-asset
				endpoint := fmt.Sprintf("/repos/%s/releases/assets/%d", OWNER_REPO, asset.id)
				req := Must(http.NewRequest("DELETE", "https://api.github.com" + endpoint, nil))
				req.Header.Set("Accept", "application/vnd.github.v3+json")
				req.Header.Set("Authorization", "Bearer " + get_pat())
				req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
				_  = Must(handle_request(req))
			}
			fallthrough

		case ACT_DOWNLOAD:
			L_INFO.Printf("Downloading %s", asset.Key)
			fh = Must(os.Create(path))

			if asset.Dl_url == "" {
				L_INFO.Printf("URL is empty, assuming %q is commited to the repo", asset.Key)
			} else if !is_dry {
				hash := sha256.New()
				req := Must(http.NewRequest("GET", asset.Dl_url, nil))
				resp := Must(HTTP_CLIENT.Do(req))

				tee_body := io.TeeReader(resp.Body, hash)
				_ = Must(io.Copy(fh, tee_body))
				Must1(resp.Body.Close())

				dl_sha256 := fmt.Sprintf("%x", hash.Sum(nil))
				if dl_sha256 != asset.Sha256 {
					L_ERROR.Fatalf("The sha256 for %q in your is incorrect: %s\nIn Plan:  %s\nDownload: %s", asset.Key, asset.Dl_url, asset.Sha256, dl_sha256)
				}
			}
			fallthrough

		case ACT_UPLOAD:
			L_INFO.Printf("Uploading %s", asset.Key)
			if fh == nil {
				fh = Must(os.Open(path))
			} else {
				_ = Must(fh.Seek(0, 0))
			}

			if !is_dry {
				file_info := Must(fh.Stat())

				// https://docs.github.com/en/rest/releases/assets?apiVersion=2022-11-28#upload-a-release-asset
				endpoint := fmt.Sprintf("/repos/%s/releases/%d/assets", OWNER_REPO, release_id)
				req := Must(http.NewRequest("POST", "https://uploads.github.com" + endpoint, fh))

				query := url.Values{}
				query.Add("name", asset.Key)
				req.URL.RawQuery = query.Encode()

				req.Header.Set("Accept", "application/vnd.github.v3+json")
				req.Header.Set("Authorization", "Bearer " + get_pat())
				req.Header.Set("X-GitHub-Api-Version", "2022-11-28")
				req.Header.Set("Content-Type", "application/octet-stream")
				req.ContentLength = file_info.Size()

				fmt.Println(string(Must(handle_request(req))))
			}

		case ACT_SKIP:
			L_DEBUG.Printf("Skipping %s", asset.Key)
		default:
			L_ERROR.Fatalf("DEV: Unknown action %d", asset.action)
		}

		//fmt.Println(asset.Key, asset.Sha256, asset.Dl_url, action)
		//fmt.Println(asset.Key, action, asset.id)
	}
}

var HTTP_CLIENT = http.Client{}

func handle_request(req *http.Request) ([]byte, error) {
	resp, err := HTTP_CLIENT.Do(req)
	if err != nil {
		L_ERROR.Fatalf("Error creating request: %s", err.Error())
	}
	defer resp.Body.Close()

	body, err := ioutil.ReadAll(resp.Body)
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("%s %q: %s\n%s", req.Method, req.URL.Path, resp.Status, string(body))
	}

	return body, err
}


func Must[T any](x T, err error) T {
	if err != nil {
		fmt.Println(err.Error())
		os.Exit(1)
	}
	return x
}
func Must1(err error) {
	if err != nil {
		fmt.Println(err.Error())
		os.Exit(1)
	}
}

func R[T ~[]byte | ~string](stdin T) io.Reader {
	return bytes.NewReader([]byte(stdin))
}

var L_DEBUG = log.New(io.Discard, "", 0)
var L_INFO = log.New(io.Discard, "", 0)
var L_ERROR = log.New(io.Discard, "", 0)
var L_STDERR = log.New(os.Stderr, "", 0) 
const (
	TRACE uint = iota 
	DEBUG
	INFO
	WARN
	ERROR
	FATAL
	PANIC
)

