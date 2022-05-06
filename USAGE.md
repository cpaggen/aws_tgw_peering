# Usage
<!--- BEGIN_TF_DOCS --->
## Requirements

| Name | Version |
|------|---------|
| aws | >= 4.4 |

## Providers

| Name | Version |
|------|---------|
| aws | >= 4.4 |
| aws.eu-west-1 | >= 4.4 |

## Inputs

No input.

## Outputs

| Name | Description |
|------|-------------|
| instance\_ip\_addresses | EC2 instances (East/West/Hub) private IPs |
| instance\_pubip\_addresses | EC2 instances (East/West/Hub) public IPs |
| remoteInstance\_ip\_address | EC2 instance (remote) private IP |
| remoteInstance\_pubip\_address | EC2 instance (remote) public IP |

<!--- END_TF_DOCS --->
