# A Terragrunt UNIT — the middle tier of the Módulo -> Unit/Stack -> Proyecto
# model. The unit holds no resource code of its own: it points at a versioned
# module and supplies inputs. That separation is the whole reason a platform
# team can own the modules while product teams only ever supply values.

# `tfr://` is Terragrunt's Terraform-registry getter. The unit names a module and
# a version — not a path and not a git ref — so the platform team can ship 1.1.0
# without touching this file, and the consumers view in the registry shows
# exactly which units are pinned to which version.
terraform {
  source = "tfr://spacelift.io/jnesspace/hello/default?version=1.0.0"
}

inputs = {
  name        = "app-storage"
  environment = "dev"
  owner       = "platform-engineering"
}
