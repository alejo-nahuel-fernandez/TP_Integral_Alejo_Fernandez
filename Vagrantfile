# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

  # --- VM Ubuntu (vmubuntu) ---
  config.vm.define "vmubuntu" do |ubuntu|
    ubuntu.vm.box = "ubuntu/focal64"
    ubuntu.vm.hostname = "vmubuntu"
    ubuntu.vm.network "private_network", ip: "192.168.56.10"
    
    ubuntu.vm.provider "virtualbox" do |vb|
      vb.name = "VM_Ubuntu"
      vb.memory = 1024
      vb.cpus = 1
    end

    # Discos para Ubuntu usando el plugin vagrant-disksize
    # Asegúrate de tenerlo instalado: vagrant plugin install vagrant-disksize
    ubuntu.vm.disk :disk, size: "5GB", name: "disk1"
    ubuntu.vm.disk :disk, size: "3GB", name: "disk2"
    ubuntu.vm.disk :disk, size: "3GB", name: "disk3"
    ubuntu.vm.disk :disk, size: "1GB", name: "disk_extra" # Disco extra no usado en LVM

    # --- Aprovisionamiento Bash para LVM en Ubuntu ---
    # La ruta es relativa a la ubicación de este Vagrantfile
    # Asegúrate de que 'configure_lvm.sh' esté dentro de 'Bash_script'
    ubuntu.vm.provision "shell", path: "Bash_script/configure_lvm.sh", privileged: true
  end

  # --- VM Fedora (vmfedora) ---
  config.vm.define "vmfedora" do |fedora| # Renombrado a 'fedora' para claridad
    fedora.vm.box = "fedora/39-cloud-base"
    fedora.vm.hostname = "vmfedora"
    fedora.vm.network "private_network", ip: "192.168.56.11"
    fedora.vm.network "forwarded_port", guest: 22, host: 2200, id: "ssh", auto_correct: true

    fedora.vm.provider "virtualbox" do |vb|
      vb.memory = "2048"
      vb.cpus = "2"
      vb.name = "VM_Fedora"

      # --- Creación y adjunción de discos para vmfedora (VERSIÓN IDEMPOTENTE) ---
      # Define los discos con sus nombres (archivos .vdi), tamaños en MB y puertos SATA.
      # El puerto se usa para identificar el disco dentro de VirtualBox.
      # El 'device' siempre es 0 para un disco HDD.
      disks = [
        { name: "fedora_disk1.vdi", size: 5120, port: 1 },  # 5GB
        { name: "fedora_disk2.vdi", size: 3072, port: 2 },  # 3GB
        { name: "fedora_disk3.vdi", size: 2048, port: 3 },  # 2GB (total 7GB para vg_datos en Fedora)
        { name: "fedora_disk_extra.vdi", size: 1024, port: 4 } # 1GB (total 1GB para vg_temp en Fedora)
      ]
      
      # Creamos un nombre de controlador diferente para Fedora para evitar conflictos futuros
      sata_controller_name = "FedoraSATAController"

      # Crea el controlador SATA si no existe. Esto es seguro de ejecutar múltiples veces.
      # VBoxManage solo lo creará si no está presente.
      vb.customize ["storagectl", :id, "--name", sata_controller_name, "--add", "sata", "--controller", "IntelAhci"]

      # Itera sobre los discos para crearlos y adjuntarlos de forma idempotente
      disks.each do |disk|
        # Obtiene la ruta completa del disco en el sistema de archivos del host
        disk_path = File.join(Dir.pwd, disk[:name])

        # Paso 1: Crear el disco si no existe en el sistema de archivos del host
        if File.exist?(disk_path)
          puts "Vagrant: Disco '#{disk[:name]}' ya existe en el host. Saltando creación."
        else
          puts "Vagrant: Creando disco '#{disk[:name]}' con tamaño #{disk[:size]}MB..."
          # El comando createhd usa la ruta relativa del filename si no se especifica un path absoluto
          vb.customize ["createhd", "--filename", disk[:name], "--size", disk[:size]]
        end

        # Paso 2: Adjuntar el disco a la VM
        begin
          puts "Vagrant: Intentando adjuntar disco '#{disk[:name]}' al puerto #{disk[:port]}..."
          vb.customize ["storageattach", :id, "--storagectl", sata_controller_name, "--port", disk[:port], "--device", 0, "--type", "hdd", "--medium", disk[:name]]
          puts "Vagrant: Disco '#{disk[:name]}' adjuntado exitosamente."
        rescue Vagrant::Errors::VBoxManageError => e
          # Este es el error más común si el disco ya está adjunto o si VBox tiene un estado inconsistente.
          # Lo ignoramos si el mensaje indica que ya está adjunto, para que Vagrant no falle.
          if e.message.include?("already exists at this controller position") || e.message.include?("already attached to this virtual machine")
            puts "Vagrant: Disco '#{disk[:name]}' ya está adjunto o en uso por VirtualBox. Saltando."
          else
            # Si es un error diferente, lo lanzamos para depuración
            raise e
          end
        end
      end
    end # Cierre de vmfedora.vm.provider "virtualbox" do |vb|
    
    # --- Aprovisionamiento Bash para LVM en Fedora ---
    # La ruta es relativa a la ubicación de este Vagrantfile
    fedora.vm.provision "shell", path: "Bash_script/configure_lvm.sh", privileged: true
  end # Cierre de config.vm.define "vmfedora" do |fedora|

end # Cierre de Vagrant.configure("2") do |config|