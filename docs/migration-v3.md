# Migration to Wiki.js 3 (blue/green)

Wiki.js 3 cannot be upgraded in place from 2.x: it needs a fresh install on PostgreSQL 17
or 18, then an export from 2.x and an import into 3.x. So the 3.x host ("green") is built
next to the 2.x host ("blue"), rehearsed on a staging name, and the production name moves
to it with one variable. Blue keeps running until the end and is the rollback.

| Phase | What | Downtime |
|---|---|---|
| 2 | Switch from Terraform to OpenTofu (no infrastructure change) | none |
| 3 | Build green: private subnet, NAT instance, v3 host, VPC origin, WAF, staging name | none |
| 4 | Rehearse: export, import, check, guest test | none |
| 5 | Cut over: freeze blue, final import, `prod_origin = "v3"` | about 1 hour read-only |
| 6 | Retire blue, connect Claude to the MCP server | none |

Phase 1 (content clean-up) happens in the `wiki-content` repository.

## What changes in the design

- **No public origin.** Today CloudFront reaches the host over plain HTTP on a public
  record, and the security group allows 80 and 443 from anywhere. Green sits in a private
  subnet with no public IP; CloudFront reaches it through a
  [VPC origin](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html),
  and its security group allows only CloudFront's origin-facing prefix list on port 80.
- **Outbound through a NAT instance** ([fck-nat](https://github.com/RaJiska/terraform-aws-fck-nat),
  t4g.nano in an auto scaling group with a static ENI). S3 goes through a free gateway endpoint.
- **AWS WAF** in front: per-IP rate limit, IP reputation, known bad inputs, and the common
  rule set with the body rules set to count (wiki pages are full of code).
- **No key pair.** Shell access is SSM Session Manager only.
- **t4g.medium** (4 GiB) for PostgreSQL 17, Wiki.js 3 and Puppeteer.

---

## Phase 2: switch to OpenTofu

1. Back up the state object (the state bucket is versioned, but take a copy anyway):

   ```bash
   aws s3 cp "s3://<state-bucket>/wiki-js-deployment/aws/marcosms-prod/wikijs/terraform.tfstate" \
     "./state-backup-$(date +%Y%m%d).tfstate" --profile <deployments-profile>
   ```

2. Install OpenTofu at the pinned version (`.opentofu-version`), e.g. `brew install opentofu`
   or `tofuenv install`.
3. Check out only the OpenTofu commit (before the v3 changes) and initialise:

   ```bash
   cd terraform
   rm -rf .terraform
   tofu init -backend-config=backend-prod.hcl
   tofu providers lock -platform=darwin_arm64 -platform=linux_amd64 -platform=linux_arm64
   tofu plan
   ```

4. The plan must say **No changes**. The Terraform lock file was removed, so OpenTofu picks
   the newest AWS provider 6.x. If the plan shows changes that come only from the provider
   version, pin `version = "6.69.1"` (the version Terraform had locked), re-run, and move up
   later on its own.
5. Commit `terraform/.terraform.lock.hcl`.

Rollback: Terraform still reads the state as long as no OpenTofu-only feature (such as
state encryption) is turned on.

## Phase 3: build green

1. Pin the images and check they have arm64 builds:

   ```bash
   scripts/pin-images.sh ghcr.io/requarks/wiki:3.0.1 postgres:17-alpine
   ```

   Paste the `tag@sha256:...` values into `packer/v3.pkrvars.hcl`. If Wiki.js 3 has no
   arm64 image, switch `v3_instance_type` to `t3.medium` and the Packer source filter to amd64.

2. Build the image and record its ID:

   ```bash
   packer build -var-file=packer/v3.pkrvars.hcl packer
   # terraform.tfvars: wikijs_v3_ami_id = "<ami from packer/manifest.json>"
   ```

3. Plan and apply. The plan should only **add** resources (subnet, route table, S3
   endpoint, NAT module, security group and rules, data volume, instance, attachment, VPC
   origin, WAF web ACL, staging distribution, DNS records). The staging name uses the
   existing `*.marcosms.com.au` certificate. Nothing existing changes while `prod_origin = "legacy"`.

   ```bash
   tofu plan -out tfplan && tofu apply tfplan && rm -f tfplan
   ```

   The VPC origin takes up to 15 minutes to deploy.

4. First boot: format and mount the data volume (once), then start Wiki.js.

   ```bash
   aws ssm start-session --target "$(tofu output -raw wikijs_v3_instance_id)"
   lsblk                                       # the 20 GiB disk without partitions
   sudo mkfs.ext4 -L app-data /dev/<nvme-device>
   sudo mount -a && df -h /data
   sudo systemctl restart docker
   sudo systemctl start wikijs && sudo systemctl status wikijs --no-pager
   ```

5. Open `https://wiki-next.marcosms.com.au` and finish setup with a temporary admin account.

## Phase 4: rehearse

1. On blue: **Administration > Utilities > Export for Wiki.js 3.x**, download the package.
2. On green: **Administration > Utilities > Import from Wiki.js 2.x**, upload it.
3. Check on green:
   - 265 pages and 77 tags, both editors (CKEditor and Markdown), Mermaid diagrams render
   - search finds text inside pages
   - users, groups and page rules came across; **private paths are not readable as a guest**
     (open `/en/private` signed out, and run the guest search below)
   - WAF: in CloudWatch, look at the `aws-common` counts while editing a few code-heavy pages
4. Git storage: point green at a **separate branch** (for example `v3`) of `wiki-content`,
   never `main` while blue is syncing. Compare the branch with `main` before cutover; v3 may
   lay files out differently.
5. Login: add an IAM Identity Center custom SAML application for the wiki (management
   account), configure the SAML strategy in Wiki.js, test sign-in with MFA, keep one local
   admin as break-glass, and turn off self-registration.

Guest search test (expect only `index/...` paths):

```bash
curl -s https://wiki-next.marcosms.com.au/graphql -H 'content-type: application/json' \
  -d '{"query":"{ pages { search(query:\"terraform\") { results { path title } } } }"}'
```

(Wiki.js 3 may expose a different API; if this query fails, use the signed-out browser test.)

## Phase 5: cut over

1. Announce a freeze to yourself: no edits on blue. In blue, turn Git storage sync off.
2. Final export from blue, import into green (or re-import over the rehearsal data).
3. Point green's Git storage at `main`.
4. Flip production to green:

   ```bash
   # terraform.tfvars
   prod_origin = "v3"
   tofu plan   # expect: wikijs_cdn origin, cache behaviour and web ACL change in place
   tofu apply
   ```

   CloudFront deploys in a few minutes. DNS does not change.

5. Move monitoring and patching to green: in `monitoring.tf`, `dashboard.tf` and
   `patching.tf`, replace `aws_instance.wikijs_prod` / the `wiki-js-prod` Name tag with the
   v3 host (separate change, plan and apply).
6. **PCA** still runs on blue and still needs the public origin. Move it before retiring
   blue: deploy PCA on green, give it its own CloudFront distribution on the same VPC origin
   (TLS at CloudFront with an ACM certificate instead of Let's Encrypt on the host), and
   switch its DNS. Until then, blue and its Elastic IP stay up.

Rollback: set `prod_origin = "legacy"` and apply. Blue is unchanged, so it serves again
within minutes (re-enable its Git sync if you turned it off).

## Phase 6: retire blue and connect Claude

1. After 2 to 4 weeks without rollback: stop blue, snapshot its data volume, then remove the
   blue resources in a separate change (instance, Elastic IP, origin record, old security
   group). The `wiki-js-legacy` t3.micro (stopped since 19 October 2026, unencrypted 20 GiB
   root volume) can go in the same change, or earlier. Remove `prevent_destroy`
   and `disable_api_termination` deliberately, one resource at a time.
2. Set `enable_v3_staging = false` and apply.
3. Wiki.js MCP server: **Administration > MCP**, enable it, give your group `use:mcp`, and
   add `https://wiki.marcosms.com.au/_mcp` as a custom connector in claude.ai with a
   read-only scope first.

## Upgrading Wiki.js

The host is disposable: an upgrade bakes a new AMI and replaces the instance.
The data volume (database, Docker data-root) moves across untouched, and
Wiki.js runs its own database migrations on first start.

1. Pin the new images and update `packer/v3.pkrvars.hcl`:
   `scripts/pin-images.sh ghcr.io/requarks/wiki:<version> postgres:17-alpine`
2. Build the AMI: `packer build -var-file=packer/v3.pkrvars.hcl packer`
3. Stop Wiki.js and snapshot the data volume (consistent restore point):
   `sudo systemctl stop wikijs` over SSM, then
   `aws ec2 create-snapshot --volume-id <wikijs_v3_data_volume_id> --description "before Wiki.js <version>"`
4. Turn termination protection off:
   `tofu apply -var v3_termination_protection=false`
5. Set `wikijs_v3_ami_id` in `terraform.tfvars` to the new AMI, then replace the host:
   `tofu apply -var v3_termination_protection=false -replace=aws_instance.wikijs_v3`
   CloudFront cannot update a VPC origin in use, so this creates a new VPC origin for the
   new instance, moves the distribution to it and deletes the old one (create_before_destroy).
   Each VPC origin and distribution change takes several minutes to deploy.
6. Check the site (`/index` as a guest, admin sign-in, Administration → System Info shows the new version), then turn protection back on: `tofu apply`.

If `wikijs.service` fails on the new host with "RWLayer of container ... is
unexpectedly nil", the Docker image store changed under the old containers.
The data is in named volumes, so recreate the containers:
`sudo docker rm -f wikijs_db wikijs && sudo systemctl restart wikijs`.

Rollback: replace the instance again with the previous AMI and restore the data
volume from the snapshot taken in step 3 (database migrations are one-way).

### Growing the root volume

With Docker's containerd image store the images live on the root disk
(`/var/lib/containerd`), not on `/data`. A new host gets `v3_root_volume_size`
and cloud-init grows the partition on first boot. To grow the running host,
raise `v3_root_volume_size`, run `tofu apply` (an in-place EBS change, no
replacement), then grow the partition and filesystem over SSM:
`growpart /dev/nvme0n1 1 && resize2fs /dev/nvme0n1p1 && df -h /`.

## Login: IAM Identity Center (SAML)

Identity Center cannot create a customer managed SAML 2.0 application through its
API, so this part lives in the console (management account, Identity Center →
Applications → Customer managed). Everything else is in Wiki.js admin.

| Where | Setting | Value |
|---|---|---|
| Identity Center app "Wiki.js" | Application ACS URL | `https://<wiki host>/_api/auth/44e69006-fffa-4f4a-ae78-ae16c391faf3/callback` |
| | Application SAML audience | `https://wiki.marcosms.com.au/saml` (stable; never changes) |
| | Attribute `Subject` | `${user:email}`, format `emailAddress` |
| | Attribute `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress` | `${user:email}` |
| | Attribute `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name` | `${user:name}` |
| | Assigned users | Marcos |
| Wiki.js strategy "AWS IAM Identity Center" | Entry point | the app's IAM Identity Center sign-in URL |
| | Issuer | `https://wiki.marcosms.com.au/saml` |
| | Certificate | the app's IAM Identity Center certificate (expires 2031-11-26) |
| | Require signed assertions / requested auth context | on / disabled (MFA sign-ins send a different context) |
| | Self-registration | off: only existing accounts can sign in |
| Wiki.js security | `trustProxy` | on (nginx passes only the CloudFront-appended client IP and `X-Forwarded-Proto https`) |

Wiki.js matches SAML logins to accounts by email: the Marcos account uses the
Identity Center user's email. The local Administrator account (passkey + 2FA)
is the break-glass login; keep Local Authentication on the login screen.

At cutover, change the Identity Center app's ACS URL and application start URL
from `wiki-next.` to `wiki.`. Before the Identity Center certificate expires,
download the new one from the app and paste it into the strategy (several can
be joined with `|` during the rotation).
