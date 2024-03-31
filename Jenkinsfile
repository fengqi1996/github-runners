def gitlab_url = 'https://gitlab.com/chan1992241/likecard.git'

pipeline {
    agent any
    environment {
        BUILD_NAME = credentials('Demo.CICD-Build-Name')
        SWR_AK = credentials('Demo.CICD-SWR-AK')
        SWR_SK = credentials('Demo.CICD-SWR-SK')
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
                    sh 'docker run --name likecard-artifact --rm -d ${BUILD_NAME}:${BUILD_NUMBER}'
                    echo "${WORKSPACE}"
                    sh 'docker cp likecard-artifact:/app ./dist'
                }
            }
        }
        stage('Push Image'){
            steps {
                sh 'docker login -u ap-southeast-3@${SWR_AK} -p ${SWR_SK} swr.ap-southeast-3.myhuaweicloud.com'
                sh 'docker push ${BUILD_NAME}:${BUILD_NUMBER}'
            }
        }
        stage('Approval')  {
            steps {
                script {
                    def messageBody = """
                    <p>Hi,</p>
                    <p>Deployment approval is required.</p>
                    <p>Please visit the <a href="${env.BUILD_URL}">Jenkins job</a> to approve.</p>
                    """
                    
                    // Trigger email for approval with job URL
                    emailext(
                        subject: "Approval Needed for Deployment",
                        body: messageBody,
                        from: 'chan1992241@gmail.com',
                        to: 'chan1992241@gmail.com',
                        replyTo: 'chan1992241@gmail.com',
                        mimeType: 'text/html'
                    )
                    // Set the chosen environment type as a global environment variable
                    env.envType = input message: 'Confirm deployment environment:', 
                                        submitter: 'Chan Jin Yee',
                                        submitterParameter: 'approverId',
                                        parameters: [choice(name: 'envType', choices: ['Pre-Prod', 'Prod'], description: 'Deployment Environment')]
                    
                    echo "Deployment approved to ${env.envType} by ${approverId}."
                }
            }
        }
        stage("Delivery to prod") {
            when {
                expression {
                    return env.envType == 'Prod'
                }
            }
            steps {
                echo "Deploying to ${env.envType}..."
                sh 'docker stop likecard-web-prod || true && docker rm likecard-web-prod || true'
                sh 'docker run --name likecard-web-prod -p 5000:80 --rm -d ${BUILD_NAME}:${BUILD_NUMBER}'
            }
        }
        stage("Delivery to pre-prod") {
            when {
                expression {
                    return env.envType == 'Pre-Prod'
                }
            }
            steps {
                echo "Deploying to ${env.envType}..."
                sh 'docker stop likecard-web-pre-prod || true && docker rm likecard-web-pre-prod || true'
                sh 'docker run --name likecard-web-pre-prod -p 8000:80 --rm -d ${BUILD_NAME}:${BUILD_NUMBER}'
            }
        }
    }
    post {
        always {
            sh 'docker stop likecard-artifact'
            sh 'docker rmi ${BUILD_NAME}:${BUILD_NUMBER} || true'
            sh 'docker image prune -f'
            echo "${WORKSPACE}"
            archiveArtifacts artifacts: 'Demo.CICD/dist/**', allowEmptyArchive: 'true'
        }
    }
}