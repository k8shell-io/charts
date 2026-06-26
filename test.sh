helm template k8shell ./k8shell  --debug      --namespace "k8shell-system"   --create-namespace   --set provisioner.targetNamespace="k8shell-workspaces"   --set sshProxy.serverKey.value="-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIFCLofjjTwJRMsYP9tO7xLAjxThiCgnsjV5n4T2t1ejCoAoGCCqGSM49
AwEHoUQDQgAE8+JTB+3urlyRSLk2y9xYVsfpdXxegb/TCnQCGzlJuuht/vFBGviN
bbScosJuqttfVYMeR+pB49L0Y9R53jrwQA==
-----END EC PRIVATE KEY-----"   --set identity.users[0].username=admin   --set identity.users[0].uid=1001   --set identity.users[0].gid=1001   --set identity.users[0].publicKey="-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw9FhcrXke0lgCoALaIsk
aJ/esxuPHsOdrl5pTCtZ5mPQm9npMEFr4I02hfgGdmY8EvgR67wg7EQ8pvzzGdEs
h1Ml/by4SniKmZDU6SNDAd0UUPM2NSMXS0J8u7kq+aWWm+a+6RDLA5qBDh22XnhS
otX90eHOH4L6o9qQRyEYiDEFJVangW71XDh1VnXSTEALLFfLB43atrqca/0nLTO6
h/VjF/EdbIeJ6TlRSN81JFQyDvuMZmaRNIoSn+ry2be20613z+3W+o03GV+gSgiQ
NQlbkp5ZfjvpWM7p1DUMsPA/vsKxrxJK1xqMIB1aLQtj0uST1bJzM6zawpxvLxIL
dwIDAQAB
-----END PUBLIC KEY-----"   --set identity.users[0].sudo="true"   --set identity.users[0].shell="/bin/bash"   --set sshProxy.nodePort.enabled="true"   --set sshProxy.nodePort.port="30022"
