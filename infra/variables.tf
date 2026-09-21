variable "key_name" {
  description = "Key_Pair Name"
  type        = string
  default     = "std08-00-key"
}

variable "owner" {
  description = "Owner"
  type        = string
  default     = "std08"
}

variable "env_type" {
  description = "Environment"
  type        = string
  default     = "lab"
}

variable "default_version" {
  description = "Default_Version"
  type        = string
  default     = "latest" # 특정 버전을 지정하고자 할 경우 문자열 형태의 숫자 기재
}
