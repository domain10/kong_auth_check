# kong-auth-check
自定义kong插件，先去服务中心进行访问控制检查，通过后再转发到上游服务器，没通过则直接返回相应的提示信息。
# 使用插件
进入/***/lua/5.1/kong，找到constants.lua文件，在文件上添加自定义插件名kong-auth-check，然后就可以通过名称直接添加了，无任何参数。
