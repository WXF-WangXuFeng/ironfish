#!/bin/bash

dos2unix map.csv

set -x
hostname=`hostname -I`
nodename=`awk -F, -v IP=$hostname '$1==IP {print($2)}' map.csv`
set +x

echo 'export IRONFISH_WALLET='${nodename} >> $HOME/.bash_profile
echo 'export IRONFISH_NODENAME='${nodename} >> $HOME/.bash_profile
echo 'export IRONFISH_THREADS='-1 >> $HOME/.bash_profile

source .bash_profile
if [ ! $IRONFISH_NODENAME ]; then
 echo "nodename not config, exit"
 exit 1
fi

wget -q -O ironfish.sh https://api.nodes.guru/ironfish.sh; 
while [ ! -s ironfish.sh ]
do
  echo "Waiting for download to complete..."
  sleep 5
done
echo download is complete, proceed with the rest of your script
# 经过测试，居然一秒钟都不到就执行了上面的一句话，都没有进 while 循环体。还是留着吧


chmod +x ironfish.sh && echo 1 | ./ironfish.sh >/dev/null 2>&1 && unalias ironfish 2>/dev/null;

while [ -z "$(which ironfish)" ]; do
  echo "ironfish command not found, waiting..."
  sleep 5
done
echo "ironfish command found!"
# 经过测试，也没有进入循环体。表明程序就像是按顺序流程走的一样，安装的时候，流程就卡在这一步，安装完了才去判断有没有铁鱼命令，而不会进入循环体


echo "chain download..."
service ironfishd stop;sleep 5;echo -e "Y\n" | ironfish chain:download >/dev/null 2>&1;sleep 5;

service ironfishd start; sleep 5; ironfish config:set enableTelemetry true;sleep 5;


echo "chain sync..."

# 这里只要检测到同步完成，下面就不用再等10分钟了，一定要注意  IDLE  和 (SYNCED) 要同时出现才行，任何一个单独出现都不行。
while true;
do
  if ironfish status | grep -z "IDLE.*(SYNCED)"; then 
    break;
  else
	echo -ne "."
    sleep 60
  fi
done

# 上面已经同步了这里就不用再等 10 分钟了
#sleep 600

echo "ironfish faucet"
echo $(date +%T)
echo -e "\n" | ironfish faucet; sleep 5;  echo -e "\n" | ironfish faucet;sleep 5;


echo "等待水到账户"

# 下面这个检查，我觉得得专门去检查 $IRON 铁鱼币才行，不然的话，如果是之前已经 mint 过的老号，如果排序排在第一名，那怎么办？老的钱包直接放弃，重新做，不过要把钱包私钥导出
while true;
do
  balance=`ironfish wallet:balance | grep Balance | cut -f3 -d' '`
  if [ -z $balance ] || [ $balance == "0.00000000" ]; then
      sleep 60
      echo -ne "."
  else
     echo "balance: $balance"
	 echo "水已到"
	 echo $(date +%T)
     break;
  fi
done

echo "ironfish mint"
cmd_mint="ironfish wallet:mint --metadata=$(ironfish config:get nodeName|sed 's/\"//g') --name=$(ironfish config:get nodeName|sed 's/\"//g')  --amount=1000 --fee=0.00000001 --confirm"
info=$(${cmd_mint} 2>&1)
echo $info

# mint 完了硬等5分钟。不需要了，因为又不做老号。新号已经可以验证上个流程是否结束
#for i in $(seq 1 60); do echo -ne ".";sleep 5;done;

# 再检查一下，这个刚mint出来的以节点名称做为币名的币的余额是否显示，没显示，或者显示为 0 都不行的
# 而当测试币数量都出来了，就表示它已经上链了，就不会出现下面要去燃烧操作了，这里mint操作还没全部上链完成。也就不会出现下面币都没有就发送转移币而报错了
while true;
do
  balance=`ironfish wallet:balances | grep "$(ironfish config:get nodeName|sed 's/\"//g') " | awk '{print $3}'`
  if [ -z $balance ] || [ $balance == "0.00000000" ]; then
      sleep 60
      echo -ne "."
  else
     echo "balance: $balance"
     break;
  fi
done

echo "ironfish burn"
cmd_burn="ironfish wallet:burn --assetId=$(ironfish wallet:balances | grep "$(ironfish config:get nodeName|sed 's/\"//g') " | awk '{print $2}')  --amount=1 --fee=0.00000001 --confirm"
info=$(${cmd_burn} 2>&1)
echo $info


# 这里不会执行了，因为上面的测试币的数量都能显示出来了，已经完全上链了
#while [[ $info =~ "error" ]];do echo "burn error";sleep 60;info=$(${cmd_burn} 2>&1);echo $info;done


# 等测试币的余额为跟之前查询的结果不一样的的时候，数据肯定上链了，不用死等了。下面那句死等的代码，可以注释掉
while true;
do
  balance2=`ironfish wallet:balances | grep "$(ironfish config:get nodeName|sed 's/\"//g') " | awk '{print $3}'`
  if [ $balance == $balance2 ]; then
      sleep 60
      echo -ne "."
  else
     echo "balance: $balance2"
     break;
  fi
done

# burn 完了，硬等5分钟
#for i in $(seq 1 6); do echo -ne ".";sleep 60;done;

echo "ironfish send"
cmd_send="ironfish wallet:send --assetId=$(ironfish wallet:balances | grep "$(ironfish config:get nodeName|sed 's/\"//g') " | awk '{print $2}') --fee=0.00000001 --amount=1 --to=dfc2679369551e64e3950e06a88e68466e813c63b100283520045925adbe59ca --confirm"

info=$(${cmd_send} 2>&1)
echo $info


# 这种错误发生在上面的燃烧操作还没上链，就走发送转移币的时候，就会报错。现在已经不需要了，上面已经验证过了
#while [[ $info =~ "Not enough" ]];do echo "send error";sleep 60;info=$(${cmd_send} 2>&1);echo $info;done


echo $nodename

#反正腾讯脚本的日志只要不删记录一直都在，就不用复制到文件保存了
info=`ironfish wallet:export`
echo $info

shutdown -t 10


