group "default" {
  targets = ["image"]
}

target "image" {
  context    = "."
  dockerfile = "Dockerfile"
  tags       = ["gnu-hurd-docker:latest"]
}

target "image-multiarch" {
  inherits  = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
}

target "ghcr" {
  inherits = ["image-multiarch"]
  tags = [
    "ghcr.io/oichkatzelesfrettschen/gnu-hurd-docker:latest"
  ]
}
