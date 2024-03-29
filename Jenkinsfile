def gitlab_url = 'https://gitlab.com/chan1992241/likecard.git'

pipeline {
    agent any
    environment {
        BUILD_NAME = credentials('Demo.CICD-Build-Name')
    }
    parameters {
        choice choices: ['Prod', 'Pre-Prod'], name: 'envType'
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
            input {
                message "Should we continue?"
                ok 'Submit'
                id 'envId'
                submitter "jinyee"
                parameters {
                    choice(choices: ['Prod', 'Pre-Prod'], name: 'envType', description: 'Deployment Environment')
                }
            }
            steps {
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