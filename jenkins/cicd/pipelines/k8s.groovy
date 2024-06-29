#! groovy https://github.com/jenkinsci/kubernetes-plugin/blob/master/src/test/resources/org/csanchez/jenkins/plugins/kubernetes/pipeline/runWithEnvVariables.groovy

def label = "k8sagent-e2e"
def home = "/home/jenkins"
def workspace = "${home}/workspace/build-jenkins-operator"
def workdir = "${workspace}/src/github.com/jenkinsci/kubernetes-operator/"
 
podTemplate(label: label,
    envVars: [
        secretEnvVar(key: 'USERNAME', secretName: 'github-username-password', secretKey: 'password')
    ],
    containers: [
        containerTemplate(name: 'alpine', image: 'alpine:3.11', ttyEnabled: true, command: 'cat'),
        containerTemplate(name: 'docker', image: 'docker:dind', ttyEnabled: true, privileged: true),
    ],
    ) {
    node(label) {
        stage('Checkout') {
            checkout([$class: 'GitSCM', branches: [[name: '*/main']], userRemoteConfigs: [[url: 'https://github.com/oversampling/github-runners.git', credentialsId: 'github-username-password']]])
        }
        stage('Run shell') {
            container('alpine') {
                sh 'echo "$USERNAME"'
                sh 'ls -la'
            }
        }
        stage('Docker') {
            container('docker') {
                sh 'docker version'
                sh 'ls -la'
                sh 'docker build -t test .'
            }
        }
    }
}