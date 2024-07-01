#! groovy https://github.com/jenkinsci/kubernetes-plugin/blob/master/src/test/resources/org/csanchez/jenkins/plugins/kubernetes/pipeline/runWithEnvVariables.groovy

def label = "k8sagent-e2e"
def home = "/home/jenkins"
def workspace = "${home}/workspace/build-jenkins-operator"
def workdir = "${workspace}/src/github.com/jenkinsci/kubernetes-operator/"
 
podTemplate(label: label,
    envVars: [
        secretEnvVar(key: 'USERNAME', secretName: 'github-username-password', secretKey: 'password'),
        secretEnvVar(key: 'SWR_AK', secretName: 'github-username-password', secretKey: 'SWR_AK'),
        secretEnvVar(key: 'SWR_SK', secretName: 'github-username-password', secretKey: 'SWR_SK'),
        secretEnvVar(key: 'BUILD_IMG', secretName: 'github-username-password', secretKey: 'BUILD_IMG'),
        secretEnvVar(key: 'KUBE_CONFIG', secretName: 'github-username-password', secretKey: 'KUBECONFIG'),
        
    ],
    containers: [
        containerTemplate(name: 'alpine', image: 'alpine:3.11', ttyEnabled: true, command: 'cat'),
        containerTemplate(name: 'docker', image: 'docker:dind', ttyEnabled: true, privileged: true),
        // containerTemplate(name: 'kubectl', image: 'bitnami/kubectl:latest'),
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
        stage('Build Push') {
            container('docker') {
                sh 'docker version'
                sh 'ls -la'
                sh 'docker login -u ap-southeast-3@${SWR_AK} -p $SWR_SK swr.ap-southeast-3.myhuaweicloud.com'
                sh 'docker build -t $BUILD_IMG:$BUILD_NUMBER .'
                sh 'docker push ${BUILD_IMG}:${BUILD_NUMBER}'
            }
        }
        stage('Deploy') {
            container('alpine') {
                sh 'apk add curl'
                sh 'curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl'
                sh 'chmod +x ./kubectl'
                sh 'mv ./kubectl /usr/local/bin'
                sh 'mkdir -p ~/.kube'
                sh 'echo $KUBE_CONFIG | base64 -d > ~/.kube/config'
                sh 'export KUBECONFIG=~/.kube/config'
                sh 'cat ~/.kube/config'
                sh 'kubectl version'
                sh 'sed -i \"s|gra-demo-image|${BUILD_IMG}:${BUILD_NUMBER}|g\" k8s.yaml'
                sh 'kubectl apply -f k8s.yaml'
            }
        }
    }
}