AWS VPC OpenVPN Python notes
============================

The below notes are python snippets leveraging `piranha_` to create an
AWS VPC with public and private subnets and a TurnKey OpenVPN NAT
instance using the server profile.

* Set required constants::

    accesskey                   # AWS Access Key ID
    secretkey                   # AWS Secret Access Key

    vpc_region                  # Example: us-east-1
    vpc_cidr                    # Example: 10.0.0.0/16

    subnet_zone                 # Example: us-east-1a
    subnet_pub_cidr             # Example: 10.0.0.0/24
    subnet_pvt_cidr             # Example: 10.0.1.0/24

    openvpn_amiid               # Refer to cloudformation_vpc_openvpn.template
    openvpn_type                # Example: m1.small
    openvpn_keypair             # Example: mykeypair
    openvpn_preseed_email       # Example: admin@example.com
    openvpn_preseed_domain      # Example: vpn.example.com

* Create connection::

    from piranha.ec2.connection import Connection
    conn = Connection(accesskey, secretkey, vpc_region)

* VPC: Create VPC::

    kwargs = {'CidrBlock': vpc_cidr}
    response = conn.send('GET', 'CreateVpc', **kwargs)
    vpc_id = response.parsed.vpc.vpcId

* VPC: Create internet gateway and attach::

    response = conn.send('GET', 'CreateInternetGateway')
    vpc_igw_id = response.parsed.internetGateway.internetGatewayId

    kwargs = {'InternetGatewayId': vpc_igw_id, 'VpcId': vpc_id}
    conn.send('GET', 'AttachInternetGateway', **kwargs)

* Public: Create subnet and setup routing::

    kwargs = {}
    kwargs['VpcId'] = vpc_id
    kwargs['CidrBlock'] = subnet_pub_cidr
    kwargs['AvailabilityZone'] = subnet_zone
    response = conn.send('GET', 'CreateSubnet', **kwargs)
    subnet_pub_id = response.parsed.subnet.subnetId

    kwargs = {'Filter.1.Name': 'vpc-id', 'Filter.1.Value.1': vpc_id}
    response = conn.send('GET', 'DescribeRouteTables', **kwargs)
    subnet_pub_rtb_id = response.parsed.routeTableSet.item.routeTableId

    kwargs = {}
    kwargs['RouteTableId'] = subnet_pub_rtb_id
    kwargs['DestinationCidrBlock'] = '0.0.0.0/0'
    kwargs['GatewayId'] = vpc_igw_id
    conn.send('GET', 'CreateRoute', **kwargs)

    kwargs = {'RouteTableId': subnet_pub_rtb_id, 'SubnetId': subnet_pub_id}
    conn.send('GET', 'AssociateRouteTable', **kwargs)

* OpenVPN: Create security group::

    openvpn_sg_name = 'openvpn-%s' % subnet_pub_id
    kwargs = {}
    kwargs['GroupName'] = openvpn_sg_name
    kwargs['GroupDescription'] = openvpn_sg_name
    kwargs['VpcId'] = vpc_id
    response = conn.send('GET', 'CreateSecurityGroup', **kwargs)
    openvpn_sg_id = response.parsed.groupId

    kwargs = {}
    kwargs['GroupId'] = openvpn_sg_id
    kwargs['IpPermissions.1.IpProtocol'] = "-1"
    kwargs['IpPermissions.1.IpRanges.1.CidrIp'] = vpc_cidr
    conn.send('GET', 'AuthorizeSecurityGroupIngress', **kwargs)

    kwargs = {}
    kwargs['GroupId'] = openvpn_sg_id
    rule_id = 1
    for rule in ['icmp:-1', 'udp:1194', 'tcp:22', 'tcp:80', 'tcp:443', 'tcp:12320', 'tcp:12321']:
        proto, port = rule.split(':')
        kwargs['IpPermissions.%s.IpProtocol' % rule_id] = proto
        kwargs['IpPermissions.%s.FromPort' % rule_id] = port
        kwargs['IpPermissions.%s.ToPort' % rule_id] = port
        kwargs['IpPermissions.%s.IpRanges.1.CidrIp' % rule_id] = '0.0.0.0/0'
        rule_id += 1
    conn.send('GET', 'AuthorizeSecurityGroupIngress', **kwargs)

* OpenVPN: Create user data for preseeding::

    openvpn_userdata = """#!/bin/bash -e
    RANDOM_PASS=$(mcookie | cut --bytes 1-8)
    cat>/etc/inithooks.conf<<EOF
    export ROOT_PASS=$RANDOM_PASS
    export HUB_APIKEY=SKIP
    export SEC_UPDATES=FORCE
    export APP_PROFILE=server
    export APP_EMAIL=%s
    export APP_DOMAIN=%s
    export APP_PRIVATE_SUBNET=%s
    export APP_VIRTUAL_SUBNET=AUTO
    EOF
    """ % (openvpn_preseed_email, openvpn_preseed_domain, subnet_pvt_cidr)

    import base64
    openvpn_userdata_b64 = base64.b64encode(openvpn_userdata)

* OpenVPN: Launch::

    kwargs = {}
    kwargs['MinCount'] = '1'
    kwargs['MaxCount'] = '1'
    kwargs['ImageId'] = openvpn_amiid
    kwargs['SecurityGroupId.1'] = openvpn_sg_id
    kwargs['InstanceType'] = openvpn_type
    kwargs['Placement.AvailabilityZone'] = subnet_zone
    kwargs['SubnetId'] = subnet_pub_id
    kwargs['UserData'] = openvpn_userdata_b64
    response = conn.send('GET', 'RunInstances', **kwargs)
    openvpn_id = response.parsed.instancesSet.item.instanceId

* OpenVPN: Enable NAT support::

    kwargs = {'InstanceId': openvpn_id, 'SourceDestCheck.Value': 'false'}
    conn.send('GET', 'ModifyInstanceAttribute', **kwargs)

* OpenVPN: Allocate and associate elastic IP::

    kwargs = {'Domain': 'vpc'}
    response = conn.send('GET', 'AllocateAddress', **kwargs)
    openvpn_eip = response.parsed.publicIp
    openvpn_eip_id = response.parsed.allocationId

    kwargs = {'AllocationId': openvpn_eip_id, 'instanceId': openvpn_id}
    conn.send('GET', 'AssociateAddress', **kwargs)

* Private: Create subnet and setup routing::

    kwargs = {'VpcId': vpc_id, 'CidrBlock': cidr_pvt, 'AvailabilityZone': zone}
    response = conn.send('GET', 'CreateSubnet', **kwargs)
    subnet_pvt_id = response.parsed.subnet.subnetId

    kwargs = {'VpcId': vpc_id}
    response = conn.send('GET', 'CreateRouteTable', **kwargs)
    subnet_pvt_rtb_id = response.parsed.routerTable.routeTableId

    kwargs = {}
    kwargs['RouteTableId'] = subnet_pvt_rtb_id
    kwargs['DestinationCidrBlock'] = '0.0.0.0/0'
    kwargs['InstanceId'] = openvpn_id
    conn.send('GET', 'CreateRoute', **kwargs)

    kwargs = {'RouteTableId': subnet_pvt_rtb_id, 'SubnetId': subnet_pvt_id}
    conn.send('GET', 'AssociateRouteTable', **kwargs)

* Private: Create security group for private subnet instances::

    subnet_pvt_sg_name = 'private-instances-%s' % subnet_pvt_id
    kwargs = {}
    kwargs['GroupName'] = subnet_pvt_sg_name
    kwargs['GroupDescription'] = subnet_pvt_sg_name
    kwargs['VpcId'] = vpc_id
    response = conn.send('GET', 'CreateSecurityGroup', **kwargs)
    subnet_pvt_sg_id = response.parsed.groupId

    kwargs = {}
    kwargs['GroupId'] = subnet_pvt_sg_id
    kwargs['IpPermissions.1.IpProtocol'] = "-1"
    kwargs['IpPermissions.1.IpRanges.1.CidrIp'] = vpc_cidr
    conn.send('GET', 'AuthorizeSecurityGroupIngress', **kwargs)

* Summary information::

    print "Create a DNS record"
    print "%s -> %s" (openvpn_preseed_domain, openvpn_eip)

    print "When launching instances in the private subnet"
    print "specify the security group id: %s" % subnet_pvt_sg_id


.. _piranha: https://github.com/turnkeylinux/piranha/

