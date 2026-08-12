# A Terragrunt UNIT — the middle tier of the Módulo -> Unit/Stack -> Proyecto
# model. The unit holds no resource code of its own: it points at a versioned
# module and supplies inputs. That separation is the whole reason a platform
# team can own the modules while product teams only ever supply values.

terraform {
  source = "../../modules/hello"
}

inputs = {
  name        = "app-storage"
  environment = "dev"
  owner       = "platform-engineering"
}
