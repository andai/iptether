# Permissions

IPTether uses the `aws` and `az` CLIs with whatever account they're signed in to. It never sees or
stores credentials. If that account can do more than IPTether needs, give IPTether a dedicated
identity with only these permissions. Then a mistake, or a compromised Mac, can only change SSH
rules on security groups.

The templates are in [`permissions/`](../permissions/).

## AWS

[`permissions/aws-iam-policy.json`](../permissions/aws-iam-policy.json):

| Action | Used for | Resource |
|---|---|---|
| `ec2:DescribeRegions` | Listing regions when `aws.regions` is empty | `*` (no resource-level permissions) |
| `ec2:DescribeSecurityGroups` | Finding security groups that allow SSH, with their names and tags | `*` (no resource-level permissions) |
| `ec2:DescribeSecurityGroupRules` | Finding IPTether's own rules and rules already allowing your IP | `*` (no resource-level permissions) |
| `ec2:AuthorizeSecurityGroupIngress` | Adding this Mac's SSH rule | Security groups only |
| `ec2:RevokeSecurityGroupIngress` | Removing an outdated rule of IPTether's | Security groups only |

It allows nothing else. It can't create or delete security groups, change egress rules or touch
instances. The policy passes AWS IAM Access Analyzer validation with no findings, and the IAM
policy simulator allows exactly these five actions.

**To apply it** to an IAM user (replace the account ID and user name):

```bash
aws iam create-policy --policy-name IPTether \
  --policy-document file://permissions/aws-iam-policy.json
aws iam attach-user-policy --user-name <user> \
  --policy-arn arn:aws:iam::<account-id>:policy/IPTether
```

With IAM Identity Center (SSO), paste the policy into a permission set as an inline policy, assign
it, and sign in with `aws sso login --profile <profile>`.

### Optional: only security groups you've tagged

To let IPTether write only to security groups you've tagged, for example `iptether=managed`, add a
condition to the second statement:

```json
"Condition": { "StringEquals": { "aws:ResourceTag/iptether": "managed" } }
```

IPTether still *looks* at every security group that allows SSH. On untagged ones its writes fail,
and the failures appear in the log and as a warning in the menu. Use `aws.regions` and the allow
list to keep runs clean.

## Azure

[`permissions/azure-custom-role.json`](../permissions/azure-custom-role.json):

| Action | Used for |
|---|---|
| `Microsoft.Network/networkSecurityGroups/read` | Listing network security groups that allow SSH, with their tags |
| `Microsoft.Network/networkSecurityGroups/securityRules/read` | Finding IPTether's rule and the priorities already in use |
| `Microsoft.Network/networkSecurityGroups/securityRules/write` | Creating or updating IPTether's rule |
| `Microsoft.Network/networkSecurityGroups/securityRules/delete` | Removing IPTether's rule |

Listing subscriptions (`az account list`) needs no role permission.

**To apply it:**

1. Replace the placeholder subscription in `AssignableScopes` with your subscription ID, or list
   several.
2. Create the role and assign it:

```bash
az role definition create --role-definition @permissions/azure-custom-role.json
az role assignment create --assignee <user-or-service-principal> \
  --role "IPTether SSH Rule Manager" \
  --scope /subscriptions/<subscription-id>
```

You can assign it at a resource-group scope instead, to limit IPTether to those groups.

## What permissions can't do

The **production exclusion** runs inside IPTether, not in AWS or Azure. You could add an IAM or
Azure deny rule for production-tagged firewalls as a second line of defense. But if IPTether
already added a rule to one of them, it then can't remove it, and every run reports a failure.
Clean those up first with "Remove My IP" (`--remove`).
