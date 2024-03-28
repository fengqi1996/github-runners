pipeline {
    agent any

    stages {
        stage('Hello') {
            steps {
                checkout([$class: 'GitSCM',
                    branches: [[name: '*/main' ]],
                    extensions: scm.extensions,
                    userRemoteConfigs: [[
                        url: 'https://gitlab.com/chan1992241/likecard.git',
                        credentialsId: 'Likecard-GitLab-Repo-Cred'
                    ]]
                ])
                sh "ls -la"
            }
        }
    }
}