#!/bin/bash
# scripts/user-data.sh — Day 21

set -e

VERSION="v4"
DEPLOY_DATE=$(date +%Y-%m-%d)

yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <title>Belinda Day 21 - ${VERSION}</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background-color: #0a1628;
      color: #ffffff;
      font-family: Georgia, serif;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      text-align: center;
    }
    .container { max-width: 600px; padding: 2rem; }
    .badge {
      display: inline-block;
      background-color: #1a3a5c;
      color: #7eb8f7;
      font-size: 0.8rem;
      letter-spacing: 0.15em;
      text-transform: uppercase;
      padding: 0.4rem 1.2rem;
      border-radius: 20px;
      margin-bottom: 2rem;
      border: 1px solid #2a5a8c;
    }
    h1 { font-size: 2.5rem; font-weight: normal; margin-bottom: 1rem; }
    .version { font-size: 1.8rem; color: #7eb8f7; font-weight: bold; margin-bottom: 1rem; }
    .meta { font-size: 0.85rem; color: #5a7a9a; margin-top: 1rem; }
    .workflow-badge {
      display: inline-block;
      background-color: #0a2d1a;
      color: #7ef7a0;
      font-size: 0.75rem;
      padding: 0.3rem 1rem;
      border-radius: 20px;
      margin-top: 1rem;
      border: 1px solid #2adc5a;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="badge">30-Day Terraform Challenge — Day 21</div>
    <h1>Hello from Belinda</h1>
    <div class="version">${VERSION}</div>
    <p>Infrastructure Deployment Workflow + CloudWatch Alarms</p>
    <div class="workflow-badge">Plan → PR → Sentinel → Approve → Apply</div>
    <p class="meta">
      Managed by Terraform Cloud | us-east-1<br/>
      Deployed: ${DEPLOY_DATE}
    </p>
  </div>
</body>
</html>
HTML
