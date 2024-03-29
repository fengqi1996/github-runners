def gitlab_url = 'https://gitlab.com/chan1992241/likecard.git'

pipeline {
    agent any
    environment {
        BUILD_NAME = credentials('Demo.CICD-Build-Name')
    }
    stages {
        stage('Clone') {
            steps {
                checkout([$class: 'GitSCM',
                    branches: [[name: '*/main' ]],
                    extensions: scm.extensions,
                    userRemoteConfigs: [[
                        url: gitlab_url,
                        credentialsId: 'Likecard-GitLab-Repo-Cred'
                    ]]
                ])
                sh "ls -la"
            }
        }
        stage('Build') {
            steps {
                dir("Demo.CICD") {
                    sh 'docker build -t ${BUILD_NAME}:${BUILD_NUMBER} .'
                    sh 'docker run --name likecard-artifact -d ${BUILD_NAME}:${BUILD_NUMBER}'
                    echo "${WORKSPACE}"
                    sh 'docker cp likecard-artifact:/app ./dist'
                }
            }
        }
        stage('Approval')  {
            steps {
                timeout(time: 1, unit: 'DAYS') {
                    input {
                        message 'Please select environment'
                        id 'envId'
                        ok 'Submit'
                        submitterParameter 'approverId'
                        parameters {
                            choice choices: ['Prod', 'Pre-Prod'], name: 'envType'
                        }
                    }
                }
                echo "Deployment approved to ${envType} by ${approverId}."
            }
        }
        stage("Deliver") {
            steps {
                echo "Delivering to ${envType}..."
            }
        }
    }
    post {
        always {
            sh 'docker stop likecard-artifact'
            sh 'docker rm likecard-artifact'
            sh 'docker rmi ${BUILD_NAME}:${BUILD_NUMBER}'
            echo "${WORKSPACE}"
            archiveArtifacts artifacts: 'Demo.CICD/dist/**', allowEmptyArchive: 'true'
        }
    }
}