NAME="territory-balancing"
PROJECT_ID="cartobq"
REGION="us-central1"
GOOGLE_REGISTRY_URL="us-central1-docker.pkg.dev"
ARTIFACTS_REPOSITORY="territory-balancing"
DOCKER_LABEL="latest"

gcloud auth configure-docker ${GOOGLE_REGISTRY_URL}
docker buildx build --platform linux/amd64 -t ${GOOGLE_REGISTRY_URL}/${PROJECT_ID}/${ARTIFACTS_REPOSITORY}/${NAME}:${DOCKER_LABEL} -f Dockerfile.base .
docker push ${GOOGLE_REGISTRY_URL}/${PROJECT_ID}/${ARTIFACTS_REPOSITORY}/${NAME}:${DOCKER_LABEL}