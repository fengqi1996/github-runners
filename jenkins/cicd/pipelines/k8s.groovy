#! groovy https://github.com/jenkinsci/kubernetes-plugin/blob/master/src/test/resources/org/csanchez/jenkins/plugins/kubernetes/pipeline/runWithEnvVariables.groovy

def label = "k8sagent-e2e"
def home = "/home/jenkins"
def workspace = "${home}/workspace/build-jenkins-operator"
def workdir = "${workspace}/src/github.com/jenkinsci/kubernetes-operator/"
 
podTemplate(label: label,
    envVars: [
        secretEnvVar(key: 'USERNAME', secretName: '', secretKey: 'password')
    ],
    containers: [
        containerTemplate(name: 'alpine', image: 'alpine:3.11', ttyEnabled: true, command: 'cat'),
    ],
    ) {
    node(label) {
        stage('Run shell') {
            container('alpine') {
                sh 'echo "$USERNAME"'
            }
        }
    }
}