//! Remote git integration: GitHub, GitLab, Bitbucket.
//!
//! Detects the hosting provider from `git remote get-url origin`,
//! stores auth tokens, and fetches PRs, issues, branches, commits and CI
//! runs via each provider's REST API.

use serde::Serialize;
use serde_json::Value;
use std::path::Path;

#[derive(Debug, Clone, Serialize, PartialEq)]
pub enum Provider {
    GitHub,
    GitLab,
    BitbucketCloud,
    BitbucketServer,
    Unknown,
}

impl Provider {
    pub fn name(&self) -> &'static str {
        match self {
            Provider::GitHub => "github",
            Provider::GitLab => "gitlab",
            Provider::BitbucketCloud => "bitbucket-cloud",
            Provider::BitbucketServer => "bitbucket-server",
            Provider::Unknown => "unknown",
        }
    }
}

/// Parsed remote info: provider, host, owner/org, repo name.
#[derive(Debug, Clone, Serialize)]
pub struct Remote {
    pub provider: Provider,
    pub host: String,
    pub owner: String,
    pub repo: String,
    pub url: String,
}

/// Detect provider and parse remote from a git directory.
pub fn detect_remote(dir: &Path) -> Option<Remote> {
    let out = std::process::Command::new("git")
        .arg("-C")
        .arg(dir)
        .args(["remote", "get-url", "origin"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let url = String::from_utf8_lossy(&out.stdout).trim().to_string();
    parse_remote_url(&url)
}

/// Parse a git remote URL into provider/host/owner/repo.
pub fn parse_remote_url(url: &str) -> Option<Remote> {
    // Handle SSH: git@github.com:owner/repo.git
    // Handle HTTPS: https://github.com/owner/repo.git
    let (host, path) = if let Some(rest) = url.strip_prefix("git@") {
        // git@host:path
        let (h, p) = rest.split_once(':')?;
        (h.to_string(), p.to_string())
    } else if let Some(rest) = url.strip_prefix("https://") {
        let (h, _) = rest.split_once('/')?;
        (h.to_string(), rest[h.len() + 1..].to_string())
    } else if let Some(rest) = url.strip_prefix("http://") {
        let (h, _) = rest.split_once('/')?;
        (h.to_string(), rest[h.len() + 1..].to_string())
    } else {
        return None;
    };

    // Strip .git suffix
    let path = path.trim_end_matches(".git").trim_end_matches('/');
    let parts: Vec<&str> = path.split('/').collect();
    if parts.len() < 2 {
        return None;
    }
    let owner = parts[0].to_string();
    let repo = parts[1].to_string();

    let provider = if host.contains("github.com") || host.contains("github") {
        Provider::GitHub
    } else if host.contains("gitlab.com") || host.contains("gitlab") {
        Provider::GitLab
    } else if host.contains("bitbucket.org") {
        Provider::BitbucketCloud
    } else if host.contains("bitbucket") {
        Provider::BitbucketServer
    } else {
        Provider::Unknown
    };

    Some(Remote {
        provider,
        host,
        owner,
        repo,
        url: url.to_string(),
    })
}

/// Auth token storage. Tokens stored in ~/.config/dotos/git-auth.json
#[derive(Debug, Clone, Serialize, serde::Deserialize, Default)]
pub struct AuthStore {
    pub accounts: Vec<Account>,
    pub default_account: Option<String>,
}

#[derive(Debug, Clone, Serialize, serde::Deserialize)]
pub struct Account {
    pub id: String,
    pub provider: String,
    pub host: String,
    pub user: String,
    pub token: String,
}

impl AuthStore {
    pub fn path() -> std::path::PathBuf {
        let home = std::env::var("HOME").unwrap_or_default();
        let config = std::env::var("XDG_CONFIG_HOME").unwrap_or_else(|_| format!("{}/.config", home));
        std::path::PathBuf::from(config).join("dotos").join("git-auth.json")
    }

    pub fn load() -> Self {
        let p = Self::path();
        if let Ok(text) = std::fs::read_to_string(&p) {
            serde_json::from_str(&text).unwrap_or_default()
        } else {
            Self::default()
        }
    }

    pub fn save(&self) -> Result<(), String> {
        let p = Self::path();
        if let Some(parent) = p.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let text = serde_json::to_string_pretty(self).map_err(|e| e.to_string())?;
        std::fs::write(&p, text).map_err(|e| e.to_string())?;
        // Set mode 600
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o600));
        }
        Ok(())
    }

    pub fn find_account(&self, provider: &str, host: &str) -> Option<&Account> {
        self.accounts.iter().find(|a| a.provider == provider && a.host == host)
    }

    pub fn find_default(&self) -> Option<&Account> {
        if let Some(id) = &self.default_account {
            self.accounts.iter().find(|a| a.id == *id)
        } else {
            self.accounts.first()
        }
    }
}

/// A pull request / merge request.
#[derive(Debug, Clone, Serialize)]
pub struct PullRequest {
    pub number: u64,
    pub title: String,
    pub state: String,
    pub author: String,
    pub branch: String,
    pub base: String,
    pub created: String,
    pub updated: String,
    pub url: String,
    pub draft: bool,
    pub review_state: String,
    pub comments: u64,
}

/// An issue.
#[derive(Debug, Clone, Serialize)]
pub struct Issue {
    pub number: u64,
    pub title: String,
    pub state: String,
    pub author: String,
    pub labels: Vec<String>,
    pub assignee: String,
    pub created: String,
    pub updated: String,
    pub url: String,
    pub comments: u64,
}

/// A branch.
#[derive(Debug, Clone, Serialize)]
pub struct Branch {
    pub name: String,
    pub commit: String,
    pub protected: bool,
}

/// A commit.
#[derive(Debug, Clone, Serialize)]
pub struct Commit {
    pub hash: String,
    pub author: String,
    pub message: String,
    pub date: String,
    pub url: String,
}

/// A CI/workflow run.
#[derive(Debug, Clone, Serialize)]
pub struct CiRun {
    pub name: String,
    pub status: String,
    pub conclusion: String,
    pub branch: String,
    pub created: String,
    pub url: String,
    pub duration_s: u64,
}

/// GitHub API client.
pub struct GitHubClient {
    pub token: String,
    pub host: String,
}

impl GitHubClient {
    pub fn new(token: &str, host: &str) -> Self {
        Self {
            token: token.to_string(),
            host: if host.is_empty() { "api.github.com".to_string() } else { host.to_string() },
        }
    }

    fn base_url(&self) -> String {
        if self.host == "api.github.com" || self.host == "github.com" {
            "https://api.github.com".to_string()
        } else {
            format!("https://{}/api/v3", self.host)
        }
    }


    fn put(&self, path: &str, body: &Value) -> Result<Value, String> {
        let url = format!("{}{}", self.base_url(), path);
        let resp = ureq::put(&url)
            .header("Authorization", &format!("Bearer {}", self.token))
            .header("Accept", "application/vnd.github+json")
            .header("X-GitHub-Api-Version", "2022-11-28")
            .header("Content-Type", "application/json")
            .send_json(body)
            .map_err(|e| {
                if let ureq::Error::StatusCode(code) = &e {
                    format!("HTTP {}", code)
                } else {
                    format!("HTTP error: {}", e)
                }
            })?;
        let body: Value = resp.into_body().read_json::<Value>().map_err(|e| format!("JSON parse error: {}", e))?;
        Ok(body)
    }

    fn patch(&self, path: &str, body: &Value) -> Result<Value, String> {
        let url = format!("{}{}", self.base_url(), path);
        let resp = ureq::patch(&url)
            .header("Authorization", &format!("Bearer {}", self.token))
            .header("Accept", "application/vnd.github+json")
            .header("X-GitHub-Api-Version", "2022-11-28")
            .header("Content-Type", "application/json")
            .send_json(body)
            .map_err(|e| {
                if let ureq::Error::StatusCode(code) = &e {
                    format!("HTTP {}", code)
                } else {
                    format!("HTTP error: {}", e)
                }
            })?;
        let body: Value = resp.into_body().read_json::<Value>().map_err(|e| format!("JSON parse error: {}", e))?;
        Ok(body)
    }

    fn get(&self, path: &str) -> Result<Value, String> {
        let url = format!("{}{}", self.base_url(), path);
        let resp = ureq::get(&url)
            .header("Authorization", &format!("Bearer {}", self.token))
            .header("Accept", "application/vnd.github+json")
            .header("X-GitHub-Api-Version", "2022-11-28")
            .call()
            .map_err(|e| {
                if let ureq::Error::StatusCode(code) = &e {
                    format!("HTTP {}", code)
                } else {
                    format!("HTTP error: {}", e)
                }
            })?;
        // check rate limit
        if let Some(remaining) = resp.headers().get("x-ratelimit-remaining").and_then(|v| v.to_str().ok()) {
            if remaining == "0" {
                if let Some(reset) = resp.headers().get("x-ratelimit-reset").and_then(|v| v.to_str().ok()) {
                    return Err(format!("Rate limited. Resets at {}", reset));
                }
                return Err("Rate limited".to_string());
            }
        }
        let body: Value = resp.into_body().read_json::<Value>().map_err(|e| format!("JSON parse error: {}", e))?;
        Ok(body)
    }

    fn post(&self, path: &str, body: &Value) -> Result<Value, String> {
        let url = format!("{}{}", self.base_url(), path);
        let resp = ureq::post(&url)
            .header("Authorization", &format!("Bearer {}", self.token))
            .header("Accept", "application/vnd.github+json")
            .header("X-GitHub-Api-Version", "2022-11-28")
            .header("Content-Type", "application/json")
            .send_json(body)
            .map_err(|e| {
                if let ureq::Error::StatusCode(code) = &e {
                    format!("HTTP {}", code)
                } else {
                    format!("HTTP error: {}", e)
                }
            })?;
        let body: Value = resp.into_body().read_json::<Value>().map_err(|e| format!("JSON parse error: {}", e))?;
        Ok(body)
    }

    pub fn list_prs(&self, owner: &str, repo: &str, state: &str) -> Result<Vec<PullRequest>, String> {
        let path = format!("/repos/{}/{}/pulls?state={}&per_page=30", owner, repo, state);
        let data = self.get(&path)?;
        let arr = data.as_array().ok_or("expected array")?;
        let mut prs = Vec::new();
        for item in arr {
            prs.push(PullRequest {
                number: item["number"].as_u64().unwrap_or(0),
                title: item["title"].as_str().unwrap_or("").to_string(),
                state: item["state"].as_str().unwrap_or("").to_string(),
                author: item["user"]["login"].as_str().unwrap_or("").to_string(),
                branch: item["head"]["ref"].as_str().unwrap_or("").to_string(),
                base: item["base"]["ref"].as_str().unwrap_or("").to_string(),
                created: item["created_at"].as_str().unwrap_or("").to_string(),
                updated: item["updated_at"].as_str().unwrap_or("").to_string(),
                url: item["html_url"].as_str().unwrap_or("").to_string(),
                draft: item["draft"].as_bool().unwrap_or(false),
                review_state: item["review_comments"].as_u64().map(|n| format!("{}", n)).unwrap_or_default(),
                comments: item["comments"].as_u64().unwrap_or(0),
            });
        }
        Ok(prs)
    }

    /// Create a new pull request.
    pub fn create_pr(&self, owner: &str, repo: &str, title: &str, body: &str, head: &str, base: &str) -> Result<PullRequest, String> {
        let path = format!("/repos/{}/{}/pulls", owner, repo);
        let payload = serde_json::json!({
            "title": title,
            "body": body,
            "head": head,
            "base": base,
        });
        let item = self.post(&path, &payload)?;
        Ok(PullRequest {
            number: item["number"].as_u64().unwrap_or(0),
            title: item["title"].as_str().unwrap_or("").to_string(),
            state: item["state"].as_str().unwrap_or("").to_string(),
            author: item["user"]["login"].as_str().unwrap_or("").to_string(),
            branch: item["head"]["ref"].as_str().unwrap_or("").to_string(),
            base: item["base"]["ref"].as_str().unwrap_or("").to_string(),
            created: item["created_at"].as_str().unwrap_or("").to_string(),
            updated: item["updated_at"].as_str().unwrap_or("").to_string(),
            url: item["html_url"].as_str().unwrap_or("").to_string(),
            draft: item["draft"].as_bool().unwrap_or(false),
            review_state: String::new(),
            comments: 0,
        })
    }

    /// Merge a pull request.
    pub fn merge_pr(&self, owner: &str, repo: &str, number: u64, method: &str) -> Result<String, String> {
        let path = format!("/repos/{}/{}/pulls/{}/merge", owner, repo, number);
        let payload = serde_json::json!({
            "merge_method": method,
        });
        let resp = self.put(&path, &payload)?;
        Ok(resp["message"].as_str().unwrap_or("merged").to_string())
    }

    /// Close a pull request.
    pub fn close_pr(&self, owner: &str, repo: &str, number: u64) -> Result<(), String> {
        let path = format!("/repos/{}/{}/pulls/{}", owner, repo, number);
        let payload = serde_json::json!({
            "state": "closed",
        });
        self.patch(&path, &payload)?;
        Ok(())
    }

    pub fn list_issues(&self, owner: &str, repo: &str, state: &str) -> Result<Vec<Issue>, String> {
        let path = format!("/repos/{}/{}/issues?state={}&per_page=30", owner, repo, state);
        let data = self.get(&path)?;
        let arr = data.as_array().ok_or("expected array")?;
        let mut issues = Vec::new();
        for item in arr {
            // Skip PRs (they appear in issues API too)
            if item.get("pull_request").is_some() {
                continue;
            }
            let labels: Vec<String> = item["labels"]
                .as_array()
                .map(|a| a.iter().filter_map(|l| l["name"].as_str().map(String::from)).collect())
                .unwrap_or_default();
            issues.push(Issue {
                number: item["number"].as_u64().unwrap_or(0),
                title: item["title"].as_str().unwrap_or("").to_string(),
                state: item["state"].as_str().unwrap_or("").to_string(),
                author: item["user"]["login"].as_str().unwrap_or("").to_string(),
                labels,
                assignee: item["assignee"]["login"].as_str().unwrap_or("").to_string(),
                created: item["created_at"].as_str().unwrap_or("").to_string(),
                updated: item["updated_at"].as_str().unwrap_or("").to_string(),
                url: item["html_url"].as_str().unwrap_or("").to_string(),
                comments: item["comments"].as_u64().unwrap_or(0),
            });
        }
        Ok(issues)
    }

    /// Create a new issue.
    pub fn create_issue(&self, owner: &str, repo: &str, title: &str, body: &str) -> Result<Issue, String> {
        let path = format!("/repos/{}/{}/issues", owner, repo);
        let payload = serde_json::json!({ "title": title, "body": body });
        let item = self.post(&path, &payload)?;
        Ok(Issue {
            number: item["number"].as_u64().unwrap_or(0),
            title: item["title"].as_str().unwrap_or("").to_string(),
            state: item["state"].as_str().unwrap_or("").to_string(),
            author: item["user"]["login"].as_str().unwrap_or("").to_string(),
            labels: vec![],
            assignee: item["assignee"]["login"].as_str().unwrap_or("").to_string(),
            created: item["created_at"].as_str().unwrap_or("").to_string(),
            updated: item["updated_at"].as_str().unwrap_or("").to_string(),
            url: item["html_url"].as_str().unwrap_or("").to_string(),
            comments: 0,
        })
    }

    /// Close an issue.
    pub fn close_issue(&self, owner: &str, repo: &str, number: u64) -> Result<(), String> {
        let path = format!("/repos/{}/{}/issues/{}", owner, repo, number);
        let payload = serde_json::json!({ "state": "closed" });
        self.patch(&path, &payload)?;
        Ok(())
    }

    pub fn list_branches(&self, owner: &str, repo: &str) -> Result<Vec<Branch>, String> {
        let path = format!("/repos/{}/{}/branches?per_page=50", owner, repo);
        let data = self.get(&path)?;
        let arr = data.as_array().ok_or("expected array")?;
        let mut branches = Vec::new();
        for item in arr {
            branches.push(Branch {
                name: item["name"].as_str().unwrap_or("").to_string(),
                commit: item["commit"]["sha"].as_str().unwrap_or("").to_string(),
                protected: item["protected"].as_bool().unwrap_or(false),
            });
        }
        Ok(branches)
    }

    pub fn list_commits(&self, owner: &str, repo: &str, limit: u32) -> Result<Vec<Commit>, String> {
        let path = format!("/repos/{}/{}/commits?per_page={}", owner, repo, limit);
        let data = self.get(&path)?;
        let arr = data.as_array().ok_or("expected array")?;
        let mut commits = Vec::new();
        for item in arr {
            commits.push(Commit {
                hash: item["sha"].as_str().unwrap_or("").to_string(),
                author: item["commit"]["author"]["name"].as_str().unwrap_or("").to_string(),
                message: item["commit"]["message"].as_str().unwrap_or("").to_string(),
                date: item["commit"]["author"]["date"].as_str().unwrap_or("").to_string(),
                url: item["html_url"].as_str().unwrap_or("").to_string(),
            });
        }
        Ok(commits)
    }

    pub fn list_ci_runs(&self, owner: &str, repo: &str) -> Result<Vec<CiRun>, String> {
        let path = format!("/repos/{}/{}/actions/runs?per_page=20", owner, repo);
        let data = self.get(&path)?;
        let arr = data["workflow_runs"].as_array().cloned().unwrap_or_default();
        let mut runs = Vec::new();
        for item in arr {
            runs.push(CiRun {
                name: item["name"].as_str().unwrap_or("").to_string(),
                status: item["status"].as_str().unwrap_or("").to_string(),
                conclusion: item["conclusion"].as_str().unwrap_or("").to_string(),
                branch: item["head_branch"].as_str().unwrap_or("").to_string(),
                created: item["created_at"].as_str().unwrap_or("").to_string(),
                url: item["html_url"].as_str().unwrap_or("").to_string(),
                duration_s: 0,
            });
        }
        Ok(runs)
    }
}

/// GitLab API client.
pub struct GitLabClient {
    pub token: String,
    pub host: String,
}

impl GitLabClient {
    pub fn new(token: &str, host: &str) -> Self {
        Self {
            token: token.to_string(),
            host: if host.is_empty() || host == "gitlab.com" { "gitlab.com".to_string() } else { host.to_string() },
        }
    }

    fn base_url(&self) -> String {
        format!("https://{}/api/v4", self.host)
    }

    fn get(&self, path: &str) -> Result<Value, String> {
        let url = format!("{}{}", self.base_url(), path);
        let mut resp = ureq::get(&url)
            .header("PRIVATE-TOKEN", &self.token)
            .call()
            .map_err(|e| format!("HTTP error: {}", e))?;
        let body: Value = resp.body_mut().read_json::<Value>().map_err(|e| format!("JSON parse error: {}", e))?;
        Ok(body)
    }

    fn project_id(&self, owner: &str, repo: &str) -> String {
        format!("{}/{}", owner, repo).replace('/', "%2F")
    }

    pub fn list_mrs(&self, owner: &str, repo: &str, state: &str) -> Result<Vec<PullRequest>, String> {
        let pid = self.project_id(owner, repo);
        let state_param = match state {
            "open" => "opened",
            "closed" => "closed",
            _ => "all",
        };
        let path = format!("/projects/{}/merge_requests?state={}&per_page=30", pid, state_param);
        let data = self.get(&path)?;
        let arr = data.as_array().ok_or("expected array")?;
        let mut prs = Vec::new();
        for item in arr {
            prs.push(PullRequest {
                number: item["iid"].as_u64().unwrap_or(0),
                title: item["title"].as_str().unwrap_or("").to_string(),
                state: item["state"].as_str().unwrap_or("").to_string(),
                author: item["author"]["username"].as_str().unwrap_or("").to_string(),
                branch: item["source_branch"].as_str().unwrap_or("").to_string(),
                base: item["target_branch"].as_str().unwrap_or("").to_string(),
                created: item["created_at"].as_str().unwrap_or("").to_string(),
                updated: item["updated_at"].as_str().unwrap_or("").to_string(),
                url: item["web_url"].as_str().unwrap_or("").to_string(),
                draft: item["draft"].as_bool().unwrap_or(false),
                review_state: String::new(),
                comments: 0,
            });
        }
        Ok(prs)
    }

    pub fn list_issues(&self, owner: &str, repo: &str, state: &str) -> Result<Vec<Issue>, String> {
        let pid = self.project_id(owner, repo);
        let path = format!("/projects/{}/issues?state={}&per_page=30", pid, state);
        let data = self.get(&path)?;
        let arr = data.as_array().ok_or("expected array")?;
        let mut issues = Vec::new();
        for item in arr {
            let labels: Vec<String> = item["labels"]
                .as_array()
                .map(|a| a.iter().filter_map(|l| l.as_str().map(String::from)).collect())
                .unwrap_or_default();
            issues.push(Issue {
                number: item["iid"].as_u64().unwrap_or(0),
                title: item["title"].as_str().unwrap_or("").to_string(),
                state: item["state"].as_str().unwrap_or("").to_string(),
                author: item["author"]["username"].as_str().unwrap_or("").to_string(),
                labels,
                assignee: item["assignee"]["username"].as_str().unwrap_or("").to_string(),
                created: item["created_at"].as_str().unwrap_or("").to_string(),
                updated: item["updated_at"].as_str().unwrap_or("").to_string(),
                url: item["web_url"].as_str().unwrap_or("").to_string(),
                comments: 0,
            });
        }
        Ok(issues)
    }

    pub fn list_branches(&self, owner: &str, repo: &str) -> Result<Vec<Branch>, String> {
        let pid = self.project_id(owner, repo);
        let path = format!("/projects/{}/repository/branches?per_page=50", pid);
        let data = self.get(&path)?;
        let arr = data.as_array().ok_or("expected array")?;
        let mut branches = Vec::new();
        for item in arr {
            branches.push(Branch {
                name: item["name"].as_str().unwrap_or("").to_string(),
                commit: item["commit"]["id"].as_str().unwrap_or("").to_string(),
                protected: item["protected"].as_bool().unwrap_or(false),
            });
        }
        Ok(branches)
    }

    pub fn list_commits(&self, owner: &str, repo: &str, limit: u32) -> Result<Vec<Commit>, String> {
        let pid = self.project_id(owner, repo);
        let path = format!("/projects/{}/repository/commits?per_page={}", pid, limit);
        let data = self.get(&path)?;
        let arr = data.as_array().ok_or("expected array")?;
        let mut commits = Vec::new();
        for item in arr {
            commits.push(Commit {
                hash: item["id"].as_str().unwrap_or("").to_string(),
                author: item["author_name"].as_str().unwrap_or("").to_string(),
                message: item["message"].as_str().unwrap_or("").to_string(),
                date: item["created_at"].as_str().unwrap_or("").to_string(),
                url: String::new(),
            });
        }
        Ok(commits)
    }

    pub fn list_pipelines(&self, owner: &str, repo: &str) -> Result<Vec<CiRun>, String> {
        let pid = self.project_id(owner, repo);
        let path = format!("/projects/{}/pipelines?per_page=20", pid);
        let data = self.get(&path)?;
        let arr = data.as_array().ok_or("expected array")?;
        let mut runs = Vec::new();
        for item in arr {
            runs.push(CiRun {
                name: item["ref"].as_str().unwrap_or("").to_string(),
                status: item["status"].as_str().unwrap_or("").to_string(),
                conclusion: String::new(),
                branch: item["ref"].as_str().unwrap_or("").to_string(),
                created: item["created_at"].as_str().unwrap_or("").to_string(),
                url: item["web_url"].as_str().unwrap_or("").to_string(),
                duration_s: 0,
            });
        }
        Ok(runs)
    }
}

/// Bitbucket Cloud API client.
pub struct BitbucketClient {
    pub user: String,
    pub app_password: String,
    pub host: String,
}

impl BitbucketClient {
    pub fn new(user: &str, token: &str, host: &str) -> Self {
        Self {
            user: user.to_string(),
            app_password: token.to_string(),
            host: if host.is_empty() { "api.bitbucket.org".to_string() } else { host.to_string() },
        }
    }

    fn base_url(&self) -> String {
        format!("https://{}", self.host)
    }

    fn get(&self, path: &str) -> Result<Value, String> {
        let url = format!("{}{}", self.base_url(), path);
        let mut resp = ureq::get(&url)
            .header("Authorization", &format!("Basic {}", base64_encode(&format!("{}:{}", self.user, self.app_password))))
            .call()
            .map_err(|e| format!("HTTP error: {}", e))?;
        let body: Value = resp.body_mut().read_json::<Value>().map_err(|e| format!("JSON parse error: {}", e))?;
        Ok(body)
    }

    pub fn list_prs(&self, owner: &str, repo: &str, state: &str) -> Result<Vec<PullRequest>, String> {
        let state_param = match state {
            "open" => "OPEN",
            "closed" => "MERGED,DECLINED",
            _ => "OPEN,MERGED,DECLINED",
        };
        let path = format!("/2.0/repositories/{}/{}/pullrequests?state={}&pagelen=30", owner, repo, state_param);
        let data = self.get(&path)?;
        let arr = data["values"].as_array().cloned().unwrap_or_default();
        let mut prs = Vec::new();
        for item in arr {
            prs.push(PullRequest {
                number: item["id"].as_u64().unwrap_or(0),
                title: item["title"].as_str().unwrap_or("").to_string(),
                state: item["state"].as_str().unwrap_or("").to_string(),
                author: item["author"]["display_name"].as_str().unwrap_or("").to_string(),
                branch: item["source"]["branch"]["name"].as_str().unwrap_or("").to_string(),
                base: item["destination"]["branch"]["name"].as_str().unwrap_or("").to_string(),
                created: item["created_on"].as_str().unwrap_or("").to_string(),
                updated: item["updated_on"].as_str().unwrap_or("").to_string(),
                url: item["links"]["html"]["href"].as_str().unwrap_or("").to_string(),
                draft: false,
                review_state: String::new(),
                comments: 0,
            });
        }
        Ok(prs)
    }

    pub fn list_issues(&self, owner: &str, repo: &str, state: &str) -> Result<Vec<Issue>, String> {
        let state_param = match state {
            "open" => "new,open",
            "closed" => "resolved,closed,invalid,wontfix,duplicate",
            _ => "",
        };
        let path = if state_param.is_empty() {
            format!("/2.0/repositories/{}/{}/issues?pagelen=30", owner, repo)
        } else {
            format!("/2.0/repositories/{}/{}/issues?state={}&pagelen=30", owner, repo, state_param)
        };
        let data = self.get(&path)?;
        let arr = data["values"].as_array().cloned().unwrap_or_default();
        let mut issues = Vec::new();
        for item in arr {
            let labels: Vec<String> = item["labels"]
                .as_array()
                .map(|a| a.iter().filter_map(|l| l.as_str().map(String::from)).collect())
                .unwrap_or_default();
            issues.push(Issue {
                number: item["id"].as_u64().unwrap_or(0),
                title: item["title"].as_str().unwrap_or("").to_string(),
                state: item["state"].as_str().unwrap_or("").to_string(),
                author: item["reporter"]["display_name"].as_str().unwrap_or("").to_string(),
                labels,
                assignee: item["assignee"]["display_name"].as_str().unwrap_or("").to_string(),
                created: item["created_on"].as_str().unwrap_or("").to_string(),
                updated: item["updated_on"].as_str().unwrap_or("").to_string(),
                url: item["links"]["html"]["href"].as_str().unwrap_or("").to_string(),
                comments: 0,
            });
        }
        Ok(issues)
    }

    pub fn list_branches(&self, owner: &str, repo: &str) -> Result<Vec<Branch>, String> {
        let path = format!("/2.0/repositories/{}/{}/refs/branches?pagelen=50", owner, repo);
        let data = self.get(&path)?;
        let arr = data["values"].as_array().cloned().unwrap_or_default();
        let mut branches = Vec::new();
        for item in arr {
            branches.push(Branch {
                name: item["name"].as_str().unwrap_or("").to_string(),
                commit: item["target"]["hash"].as_str().unwrap_or("").to_string(),
                protected: false,
            });
        }
        Ok(branches)
    }

    pub fn list_commits(&self, owner: &str, repo: &str, limit: u32) -> Result<Vec<Commit>, String> {
        let path = format!("/2.0/repositories/{}/{}/commits?pagelen={}", owner, repo, limit);
        let data = self.get(&path)?;
        let arr = data["values"].as_array().cloned().unwrap_or_default();
        let mut commits = Vec::new();
        for item in arr {
            commits.push(Commit {
                hash: item["hash"].as_str().unwrap_or("").to_string(),
                author: item["author"]["raw"].as_str().unwrap_or("").to_string(),
                message: item["message"].as_str().unwrap_or("").to_string(),
                date: item["date"].as_str().unwrap_or("").to_string(),
                url: String::new(),
            });
        }
        Ok(commits)
    }
}

fn base64_encode(input: &str) -> String {
    // Simple base64 encoding
    const CHARS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let bytes = input.as_bytes();
    let mut result = String::new();
    let mut i = 0;
    while i < bytes.len() {
        let b0 = bytes[i] as u32;
        let b1 = if i + 1 < bytes.len() { bytes[i + 1] as u32 } else { 0 };
        let b2 = if i + 2 < bytes.len() { bytes[i + 2] as u32 } else { 0 };
        let n = (b0 << 16) | (b1 << 8) | b2;
        result.push(CHARS[((n >> 18) & 63) as usize] as char);
        result.push(CHARS[((n >> 12) & 63) as usize] as char);
        if i + 1 < bytes.len() {
            result.push(CHARS[((n >> 6) & 63) as usize] as char);
        } else {
            result.push('=');
        }
        if i + 2 < bytes.len() {
            result.push(CHARS[(n & 63) as usize] as char);
        } else {
            result.push('=');
        }
        i += 3;
    }
    result
}

/// Fetch remote status for a project directory.
pub fn project_remote_status(dir: &Path) -> Value {
    let remote = match detect_remote(dir) {
        Some(r) => r,
        None => return serde_json::json!({ "error": "no remote detected" }),
    };

    let auth = AuthStore::load();
    let account = auth.find_account(remote.provider.name(), &remote.host)
        .or_else(|| auth.find_default());

    match remote.provider {
        Provider::GitHub | Provider::GitLab => {
            let gitlab = remote.provider == Provider::GitLab;
            let token = token_for(&remote, account);
            // every call's failure is kept and shown (a bad token is "HTTP 401", not an empty list)
            let mut errors: Vec<String> = Vec::new();
            let mut keep = |what: &str, r: Result<Value, String>| -> Value {
                r.unwrap_or_else(|e| {
                    errors.push(format!("{what}: {e}"));
                    serde_json::json!([])
                })
            };
            let (prs, issues, branches, commits, ci) = if gitlab {
                let c = GitLabClient::new(&token, &remote.host);
                (
                    keep("merge requests", c.list_mrs(&remote.owner, &remote.repo, "open").and_then(to_json)),
                    keep("issues", c.list_issues(&remote.owner, &remote.repo, "open").and_then(to_json)),
                    keep("branches", c.list_branches(&remote.owner, &remote.repo).and_then(to_json)),
                    keep("commits", c.list_commits(&remote.owner, &remote.repo, 10).and_then(to_json)),
                    keep("pipelines", c.list_pipelines(&remote.owner, &remote.repo).and_then(to_json)),
                )
            } else {
                let c = GitHubClient::new(&token, &remote.host);
                (
                    keep("pull requests", c.list_prs(&remote.owner, &remote.repo, "open").and_then(to_json)),
                    keep("issues", c.list_issues(&remote.owner, &remote.repo, "open").and_then(to_json)),
                    keep("branches", c.list_branches(&remote.owner, &remote.repo).and_then(to_json)),
                    keep("commits", c.list_commits(&remote.owner, &remote.repo, 10).and_then(to_json)),
                    keep("CI runs", c.list_ci_runs(&remote.owner, &remote.repo).and_then(to_json)),
                )
            };
            serde_json::json!({
                "provider": remote.provider.name(),
                "host": remote.host,
                "owner": remote.owner,
                "repo": remote.repo,
                "url": remote.url,
                "authenticated": !token.is_empty(),
                "pull_requests": prs,
                "issues": issues,
                "branches": branches,
                "commits": commits,
                "ci_runs": ci,
                "errors": errors,
            })
        }
        Provider::BitbucketCloud => {
            let (user, token) = account.map(|a| (a.user.clone(), a.token.clone())).unwrap_or_default();
            let client = BitbucketClient::new(&user, &token, &remote.host);
            let prs = client.list_prs(&remote.owner, &remote.repo, "open").unwrap_or_default();
            let issues = client.list_issues(&remote.owner, &remote.repo, "open").unwrap_or_default();
            let branches = client.list_branches(&remote.owner, &remote.repo).unwrap_or_default();
            let commits = client.list_commits(&remote.owner, &remote.repo, 10).unwrap_or_default();
            serde_json::json!({
                "provider": remote.provider.name(),
                "host": remote.host,
                "owner": remote.owner,
                "repo": remote.repo,
                "url": remote.url,
                "authenticated": !token.is_empty(),
                "pull_requests": prs,
                "issues": issues,
                "branches": branches,
                "commits": commits,
                "ci_runs": [],
            })
        }
        _ => serde_json::json!({
            "provider": remote.provider.name(),
            "host": remote.host,
            "owner": remote.owner,
            "repo": remote.repo,
            "url": remote.url,
            "authenticated": false,
            "error": "provider not supported yet",
        }),
    }
}

/// The token for a remote: a connected account's (placeholders skipped), else the host's own CLI
/// login (`gh auth token`, glab's token), else GITHUB_TOKEN / GITLAB_TOKEN.
fn token_for(remote: &Remote, account: Option<&Account>) -> String {
    if let Some(t) = account.map(|a| a.token.trim()).filter(|t| t.len() >= 20) {
        return t.to_string();
    }
    let host = if remote.host.is_empty() { if remote.provider == Provider::GitLab { "gitlab.com" } else { "github.com" } } else { remote.host.as_str() };
    let cli = |cmd: &str, args: &[&str]| -> Option<String> {
        // a CLI waiting on its keyring must not stall the page: 5 s at most
        let out = std::process::Command::new("timeout").arg("5").arg(cmd).args(args).output().ok()?;
        let t = String::from_utf8_lossy(&out.stdout).trim().to_string();
        (out.status.success() && !t.is_empty()).then_some(t)
    };
    let found = match remote.provider {
        Provider::GitLab => cli("glab", &["config", "get", "token", "--host", host]),
        _ => cli("gh", &["auth", "token", "--hostname", host]),
    };
    found.or_else(|| std::env::var(if remote.provider == Provider::GitLab { "GITLAB_TOKEN" } else { "GITHUB_TOKEN" }).ok().filter(|t| !t.is_empty())).unwrap_or_default()
}

fn to_json<T: Serialize>(v: T) -> Result<Value, String> {
    serde_json::to_value(v).map_err(|e| e.to_string())
}
